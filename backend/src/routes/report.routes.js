import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';

const router = Router();
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
export default router;
