import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';

const router = Router();
const schema = z.object({ routeId: z.string(), stopId: z.string(), present: z.boolean() });
router.post('/', requireAuth(['parent', 'student']), async (req, res) => {
  const input = schema.parse(req.body);
  await pool.query(`insert into presences(user_id, route_id, stop_id, service_date, present) values ($1, $2, $3, current_date, $4) on conflict(user_id, route_id, stop_id, service_date) do update set present=excluded.present, updated_at=now()`, [req.user.sub, input.routeId, input.stopId, input.present]);
  res.status(204).end();
});
export default router;
