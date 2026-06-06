import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';

const router = Router();
const favoriteSchema = z.object({
  routeExternalId: z.string().min(1),
  routeName: z.string().min(1),
  routeShortName: z.string().optional().default(''),
});
const settingsSchema = z.object({ enabled: z.boolean() });

router.use(requireAuth(['parent', 'student']));

router.get('/settings', async (req, res) => {
  const { rows } = await pool.query(
    `insert into passenger_notification_settings(user_id, enabled)
     values ($1, true)
     on conflict (user_id) do update set user_id=excluded.user_id
     returning enabled`,
    [req.user.sub],
  );
  res.json({ notificationsEnabled: rows[0].enabled });
});

router.put('/settings', async (req, res) => {
  const input = settingsSchema.parse(req.body);
  const { rows } = await pool.query(
    `insert into passenger_notification_settings(user_id, enabled, updated_at)
     values ($1, $2, now())
     on conflict (user_id) do update set enabled=excluded.enabled, updated_at=now()
     returning enabled`,
    [req.user.sub, input.enabled],
  );
  res.json({ notificationsEnabled: rows[0].enabled });
});

router.get('/favorites', async (req, res) => {
  const { rows } = await pool.query(
    `select route_external_id as "routeExternalId", route_name as "routeName", route_short_name as "routeShortName", created_at as "createdAt"
     from passenger_favorite_routes
     where user_id=$1
     order by created_at desc`,
    [req.user.sub],
  );
  res.json(rows);
});

router.post('/favorites', async (req, res) => {
  const input = favoriteSchema.parse(req.body);
  const { rows } = await pool.query(
    `insert into passenger_favorite_routes(user_id, route_external_id, route_name, route_short_name)
     values ($1, $2, $3, $4)
     on conflict (user_id, route_external_id)
     do update set route_name=excluded.route_name, route_short_name=excluded.route_short_name
     returning route_external_id as "routeExternalId", route_name as "routeName", route_short_name as "routeShortName"`,
    [req.user.sub, input.routeExternalId, input.routeName, input.routeShortName],
  );
  res.status(201).json(rows[0]);
});

router.delete('/favorites/:routeExternalId', async (req, res) => {
  await pool.query('delete from passenger_favorite_routes where user_id=$1 and route_external_id=$2', [req.user.sub, req.params.routeExternalId]);
  res.status(204).end();
});

router.get('/alerts', async (req, res) => {
  const { rows } = await pool.query(
    `select d.id, d.status, d.reason, d.created_at,
            coalesce(d.route_external_id, d.route_id::text) as route_external_id,
            coalesce(d.route_name, r.name, f.route_name, 'Ligne scolaire') as route_name
     from delays d
     join passenger_favorite_routes f on f.user_id=$1 and f.route_external_id=coalesce(d.route_external_id, d.route_id::text)
     left join school_routes r on r.id=d.route_id
     where d.created_at > now() - interval '7 days'
     order by d.created_at desc
     limit 30`,
    [req.user.sub],
  );
  res.json({
    alerts: rows.map((row) => ({
      id: row.id,
      routeExternalId: row.route_external_id,
      routeName: row.route_name,
      status: row.status,
      reason: row.reason,
      message: `${row.route_name} : ${row.status} suite à ${row.reason}.`,
      createdAt: row.created_at,
      severity: row.status.toLowerCase().includes('retard') ? 'warning' : 'info',
    })),
  });
});

export default router;
