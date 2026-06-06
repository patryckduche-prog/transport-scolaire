import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';

const router = Router();
const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const schema = z.object({
  routeId: z.string(),
  routeName: z.string().optional(),
  latitude: z.number(),
  longitude: z.number(),
  speed: z.number().optional(),
});

router.post('/', requireAuth(['driver']), async (req, res) => {
  const input = schema.parse(req.body);
  const uuidRoute = uuidRegex.test(input.routeId);
  await pool.query(
    `insert into gps_positions(route_id, route_external_id, route_name, driver_id, latitude, longitude, speed)
     values ($1,$2,$3,$4,$5,$6,$7)`,
    [uuidRoute ? input.routeId : null, uuidRoute ? input.routeId : input.routeId, input.routeName ?? null, req.user.sub, input.latitude, input.longitude, input.speed ?? 0],
  );
  res.status(204).end();
});

router.get('/latest/:routeId', requireAuth(), async (req, res) => {
  const uuidRoute = uuidRegex.test(req.params.routeId);
  const { rows } = await pool.query(
    `select * from gps_positions
     where ${uuidRoute ? 'route_id=$1' : 'route_external_id=$1'}
     order by recorded_at desc
     limit 1`,
    [req.params.routeId],
  );
  res.json(rows[0] ?? null);
});

export default router;
