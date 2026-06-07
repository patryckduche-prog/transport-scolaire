import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';
import { detectStopEntry } from '../services/geofence.service.js';
import { broadcastRealtime } from '../services/realtime.service.js';
import { activeRouteSuspension, suspensionPayload } from '../services/route-alerts.service.js';

const router = Router();

const startSchema = z.object({
  routeId: z.string().min(1),
  routeName: z.string().min(1),
  vehicleId: z.string().uuid().optional(),
});
const gpsSchema = z.object({
  latitude: z.number(),
  longitude: z.number(),
  speed: z.number().optional().default(0),
  recordedAt: z.string().optional(),
});
const presenceSchema = z.object({
  present: z.boolean(),
  status: z.enum(['expected', 'present', 'absent', 'not_seen']).optional(),
});
const absenceSchema = z.object({
  routeExternalId: z.string().min(1),
  studentId: z.string().uuid(),
  absent: z.boolean().default(true),
});
const incidentSchema = z.object({
  type: z.string().min(1),
  message: z.string().min(1),
  severity: z.string().optional().default('warning'),
});
const finishCheckSchema = z.object({
  allStudentsChecked: z.boolean(),
  busEmptyConfirmed: z.boolean(),
  comment: z.string().optional().default(''),
});

router.use(requireAuth());

router.post('/start', requireAuth(['driver']), async (req, res) => {
  const input = startSchema.parse(req.body);
  const suspension = await activeRouteSuspension(pool, input.routeId, input.routeName);
  if (suspension) {
    return res.status(423).json({
      error: 'route_suspended',
      message: 'TRANSPORTS INTERDITS',
      alert: suspensionPayload(suspension),
    });
  }
  const { rows } = await pool.query(
    `insert into daily_runs(route_external_id, route_name, driver_id, vehicle_id, status)
     values ($1, $2, $3, $4, 'started')
     returning *`,
    [input.routeId, input.routeName, req.user.sub, input.vehicleId ?? null],
  );
  const run = rows[0];
  await pool.query(
    `insert into daily_run_student_presence(run_id, student_id, expected, status)
     select $1, sra.student_id, true, 'expected'
     from student_route_assignments sra
     where sra.route_external_id=$2 and sra.active=true
     on conflict (run_id, student_id) do nothing`,
    [run.id, input.routeId],
  );
  broadcastRealtime({ type: 'run.started', runId: run.id, routeId: input.routeId, routeName: input.routeName });
  res.status(201).json(run);
});

router.get('/current', requireAuth(['driver']), async (req, res) => {
  const { rows } = await pool.query(
    `select * from daily_runs
     where driver_id=$1 and status in ('started','paused') and service_date=current_date
     order by started_at desc limit 1`,
    [req.user.sub],
  );
  res.json(rows[0] ?? null);
});

router.get('/:runId/students', requireAuth(['driver', 'company', 'region']), async (req, res) => {
  const { rows } = await pool.query(
    `select s.id, s.first_name as "firstName", s.last_name as "lastName", s.photo_url as "photoUrl",
            sra.stop_external_id as "stopExternalId", sra.stop_name as "stopName",
            coalesce(p.status, 'expected') as status, p.present as present
     from daily_runs r
     join student_route_assignments sra on sra.route_external_id=r.route_external_id and sra.active=true
     join students s on s.id=sra.student_id and s.active=true
     left join daily_run_student_presence p on p.run_id=r.id and p.student_id=s.id
     where r.id=$1
     order by sra.stop_name, s.last_name, s.first_name`,
    [req.params.runId],
  );
  res.json(rows);
});

router.post('/:runId/gps', requireAuth(['driver']), async (req, res) => {
  const input = gpsSchema.parse(req.body);
  const { rows: runRows } = await pool.query('select * from daily_runs where id=$1 and driver_id=$2', [req.params.runId, req.user.sub]);
  const run = runRows[0];
  if (!run) return res.status(404).json({ error: 'run_not_found' });

  await pool.query(
    `insert into gps_positions(route_external_id, route_name, driver_id, latitude, longitude, speed, recorded_at)
     values ($1, $2, $3, $4, $5, $6, coalesce($7::timestamptz, now()))`,
    [run.route_external_id, run.route_name, req.user.sub, input.latitude, input.longitude, input.speed, input.recordedAt ?? null],
  );

  const { rows: stops } = await pool.query(
    `select stop_external_id, stop_name, latitude, longitude, radius_meters
     from route_stop_geofences
     where route_external_id=$1 and active=true`,
    [run.route_external_id],
  );
  const match = detectStopEntry(input, stops);
  if (match) {
    await pool.query(
      `insert into daily_run_stop_events(run_id, stop_external_id, stop_name, event_type, distance_meters)
       values ($1, $2, $3, 'approaching', $4)
       on conflict (run_id, stop_external_id, event_type) do nothing`,
      [run.id, match.stop_external_id, match.stop_name, match.distanceMeters],
    );
    broadcastRealtime({
      type: 'run.stop.approaching',
      runId: run.id,
      routeId: run.route_external_id,
      stopExternalId: match.stop_external_id,
      stopName: match.stop_name,
      distanceMeters: Math.round(match.distanceMeters),
    });
  }
  broadcastRealtime({ type: 'run.gps', runId: run.id, routeId: run.route_external_id, latitude: input.latitude, longitude: input.longitude });
  res.json({ ok: true, stopMatch: match ? { stopExternalId: match.stop_external_id, stopName: match.stop_name, distanceMeters: Math.round(match.distanceMeters) } : null });
});

router.post('/:runId/stops/:stopExternalId/arrive', requireAuth(['driver']), async (req, res) => {
  const stopName = String(req.body?.stopName ?? req.params.stopExternalId);
  const { rows } = await pool.query(
    `insert into daily_run_stop_events(run_id, stop_external_id, stop_name, event_type)
     values ($1, $2, $3, 'arrived')
     on conflict (run_id, stop_external_id, event_type) do update set event_at=now()
     returning *`,
    [req.params.runId, req.params.stopExternalId, stopName],
  );
  broadcastRealtime({ type: 'run.stop.arrived', runId: req.params.runId, stopExternalId: req.params.stopExternalId, stopName });
  res.status(201).json(rows[0]);
});

router.post('/:runId/students/:studentId/presence', requireAuth(['driver']), async (req, res) => {
  const input = presenceSchema.parse(req.body);
  const status = input.status ?? (input.present ? 'present' : 'not_seen');
  const { rows } = await pool.query(
    `insert into daily_run_student_presence(run_id, student_id, expected, present, status, updated_by, updated_at)
     values ($1, $2, true, $3, $4, $5, now())
     on conflict (run_id, student_id)
     do update set present=excluded.present, status=excluded.status, updated_by=excluded.updated_by, updated_at=now()
     returning *`,
    [req.params.runId, req.params.studentId, input.present, status, req.user.sub],
  );
  broadcastRealtime({ type: 'run.student.presence', runId: req.params.runId, studentId: req.params.studentId, status });
  res.json(rows[0]);
});

router.post('/absence', requireAuth(['parent', 'student']), async (req, res) => {
  const input = absenceSchema.parse(req.body);
  const status = input.absent ? 'absent' : 'expected';
  const { rows } = await pool.query(
    `update daily_run_student_presence p
     set present=$1, status=$2, updated_by=$3, updated_at=now()
     from daily_runs r
     where p.run_id=r.id and r.route_external_id=$4 and r.service_date=current_date and p.student_id=$5
     returning p.*`,
    [!input.absent, status, req.user.sub, input.routeExternalId, input.studentId],
  );
  broadcastRealtime({ type: 'run.student.absence', routeId: input.routeExternalId, studentId: input.studentId, status });
  res.json({ updated: rows.length, status });
});

router.post('/:runId/incidents', requireAuth(['driver']), async (req, res) => {
  const input = incidentSchema.parse(req.body);
  const { rows } = await pool.query(
    `insert into run_incidents(run_id, driver_id, type, message, severity)
     values ($1, $2, $3, $4, $5) returning *`,
    [req.params.runId, req.user.sub, input.type, input.message, input.severity],
  );
  broadcastRealtime({ type: 'run.incident', runId: req.params.runId, incidentType: input.type, severity: input.severity, message: input.message });
  res.status(201).json(rows[0]);
});

router.post('/:runId/finish-check', requireAuth(['driver']), async (req, res) => {
  const input = finishCheckSchema.parse(req.body);
  const { rows } = await pool.query(
    `insert into run_finish_checks(run_id, driver_id, all_students_checked, bus_empty_confirmed, comment, checked_at)
     values ($1, $2, $3, $4, $5, now())
     on conflict (run_id) do update set all_students_checked=excluded.all_students_checked,
       bus_empty_confirmed=excluded.bus_empty_confirmed, comment=excluded.comment, checked_at=now()
     returning *`,
    [req.params.runId, req.user.sub, input.allStudentsChecked, input.busEmptyConfirmed, input.comment],
  );
  if (input.allStudentsChecked && input.busEmptyConfirmed) {
    await pool.query(`update daily_runs set status='finished', finished_at=now() where id=$1`, [req.params.runId]);
  }
  broadcastRealtime({ type: 'run.finish_check', runId: req.params.runId, completed: input.allStudentsChecked && input.busEmptyConfirmed });
  res.json(rows[0]);
});

export default router;
