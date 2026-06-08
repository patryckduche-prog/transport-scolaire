import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';

const router = Router();
const incidentStatusSchema = z.object({
  status: z.enum(['received', 'in_progress', 'closed']),
  comment: z.string().optional().default(''),
});

router.use(requireAuth(['company', 'region', 'driver']));

router.get('/dashboard', async (_, res) => {
  const [present, delays, routes] = await Promise.all([
    pool.query('select count(*)::int as count from presences where service_date=current_date and present'),
    pool.query('select count(*)::int as count from delays where created_at::date=current_date'),
    pool.query('select count(*)::int as count from school_routes'),
  ]);
  res.json({ presentToday: present.rows[0].count, delaysToday: delays.rows[0].count, routes: routes.rows[0].count });
});

router.get('/attendance/monthly', async (_, res) => {
  const { rows } = await pool.query(`select date_trunc('month', service_date)::date as month, route_id, count(*) filter(where present)::int as present_count from presences group by 1, route_id order by 1 desc`);
  res.json(rows);
});

router.get('/incidents', requireAuth(['company', 'region']), async (_, res) => {
  const { rows } = await pool.query(
    `select i.id,
            i.run_id as "runId",
            i.type,
            i.reason,
            i.message,
            i.severity,
            i.status,
            i.route_external_id as "routeExternalId",
            coalesce(i.route_name, r.route_name) as "routeName",
            coalesce(i.driver_name, u.name) as "driverName",
            coalesce(i.driver_email, u.email) as "driverEmail",
            coalesce(i.vehicle_plate, v.plate_number) as "vehiclePlate",
            i.latitude::float as latitude,
            i.longitude::float as longitude,
            i.speed::float as speed,
            i.created_at as "createdAt",
            i.status_updated_at as "statusUpdatedAt",
            updater.name as "statusUpdatedBy"
     from run_incidents i
     left join daily_runs r on r.id=i.run_id
     left join users u on u.id=i.driver_id
     left join vehicles v on v.id=coalesce(i.vehicle_id, r.vehicle_id)
     left join users updater on updater.id=i.status_updated_by
     order by i.created_at desc
     limit 100`,
  );
  res.json(rows);
});

router.patch('/incidents/:incidentId/status', requireAuth(['company', 'region']), async (req, res) => {
  const input = incidentStatusSchema.parse(req.body);
  const acknowledgedAt = input.status === 'in_progress' ? 'now()' : 'acknowledged_at';
  const closedAt = input.status === 'closed' ? 'now()' : 'closed_at';
  const { rows } = await pool.query(
    `update run_incidents
     set status=$1,
         status_updated_by=$2,
         status_updated_at=now(),
         acknowledged_at=${acknowledgedAt},
         closed_at=${closedAt}
     where id=$3
     returning *`,
    [input.status, req.user.sub, req.params.incidentId],
  );
  if (!rows[0]) return res.status(404).json({ error: 'incident_not_found' });
  await pool.query(
    `insert into run_incident_status_history(incident_id, status, changed_by, comment)
     values ($1, $2, $3, $4)`,
    [req.params.incidentId, input.status, req.user.sub, input.comment],
  );
  res.json(rows[0]);
});

router.get('/incidents/:incidentId/history', requireAuth(['company', 'region']), async (req, res) => {
  const { rows } = await pool.query(
    `select h.id, h.status, h.comment, h.changed_at as "changedAt", u.name as "changedBy"
     from run_incident_status_history h
     left join users u on u.id=h.changed_by
     where h.incident_id=$1
     order by h.changed_at asc`,
    [req.params.incidentId],
  );
  res.json(rows);
});

export default router;
