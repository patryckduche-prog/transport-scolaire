import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';
import { sendDelayNotification } from '../services/fcm.service.js';

const router = Router();
const schema = z.object({ routeId: z.string(), routeName: z.string().optional(), status: z.string(), reason: z.string() });
router.post('/', requireAuth(['driver']), async (req, res) => {
  const input = schema.parse(req.body);
  const uuidRoute = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.routeId);
  const { rows } = await pool.query(
    `insert into delays(route_id, route_external_id, route_name, driver_id, status, reason)
     values ($1, $2, $3, $4, $5, $6)
     returning *`,
    [uuidRoute ? input.routeId : null, uuidRoute ? input.routeId : input.routeId, input.routeName ?? null, req.user.sub, input.status, input.reason],
  );
  await sendDelayNotification(input.routeId, `Bus ${input.routeName ?? input.routeId} : ${input.status} suite a ${input.reason}.`);
  res.status(201).json(rows[0]);
});
export default router;
