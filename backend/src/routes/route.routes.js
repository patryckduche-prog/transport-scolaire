import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';

const router = Router();
router.use(requireAuth());
router.get('/', async (_, res) => {
  const { rows } = await pool.query(`
    select r.id, r.name, coalesce(v.plate_number, 'Non affecte') as vehicle,
      coalesce(json_agg(json_build_object('id', s.id, 'name', s.name, 'scheduledTime', rs.scheduled_time, 'latitude', s.latitude, 'longitude', s.longitude, 'presentCount', coalesce(p.present_count,0), 'absentCount', coalesce(p.absent_count,0)) order by rs.sequence) filter (where s.id is not null), '[]') as stops
    from school_routes r
    left join vehicles v on v.id = r.vehicle_id
    left join route_stops rs on rs.route_id = r.id
    left join stops s on s.id = rs.stop_id
    left join lateral (select count(*) filter(where present) as present_count, count(*) filter(where not present) as absent_count from presences where route_id = r.id and stop_id = s.id and service_date = current_date) p on true
    group by r.id, v.plate_number order by r.name`);
  res.json(rows);
});
export default router;
