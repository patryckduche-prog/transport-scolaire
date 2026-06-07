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
const settingsSchema = z.object({
  enabled: z.boolean(),
  premiumTestEnabled: z.boolean().optional(),
});
const absenceSchema = z.object({
  routeExternalId: z.string().min(1),
  routeName: z.string().optional().default(''),
  absent: z.boolean().default(true),
});

async function ensurePassengerColumns() {
  await pool.query('alter table passenger_notification_settings add column if not exists premium_test_enabled boolean not null default false');
  await pool.query(`
    create table if not exists passenger_absence_reports (
      user_id uuid references users(id) on delete cascade,
      route_external_id text not null,
      route_name text not null default '',
      service_date date not null default current_date,
      absent boolean not null default true,
      updated_at timestamptz not null default now(),
      primary key(user_id, route_external_id, service_date)
    )
  `);
  await pool.query(`
    create table if not exists passenger_hidden_alerts (
      user_id uuid references users(id) on delete cascade,
      delay_id bigint references delays(id) on delete cascade,
      hidden_at timestamptz not null default now(),
      primary key(user_id, delay_id)
    )
  `);
}

async function getPassengerSettings(userId) {
  await ensurePassengerColumns();
  const { rows } = await pool.query(
    `insert into passenger_notification_settings(user_id, enabled)
     values ($1, true)
     on conflict (user_id) do update set user_id=excluded.user_id
     returning enabled, premium_test_enabled`,
    [userId],
  );
  return {
    notificationsEnabled: rows[0].enabled,
    premiumEnabled: rows[0].premium_test_enabled === true,
    premiumTestEnabled: rows[0].premium_test_enabled === true,
  };
}

router.use(requireAuth(['parent', 'student']));

router.get('/settings', async (req, res) => {
  res.json(await getPassengerSettings(req.user.sub));
});

router.put('/settings', async (req, res) => {
  const input = settingsSchema.parse(req.body);
  await ensurePassengerColumns();
  const { rows } = await pool.query(
    `insert into passenger_notification_settings(user_id, enabled, premium_test_enabled, updated_at)
     values ($1, $2, coalesce($3::boolean, false), now())
     on conflict (user_id) do update set
       enabled=excluded.enabled,
       premium_test_enabled=coalesce($3::boolean, passenger_notification_settings.premium_test_enabled),
       updated_at=now()
     returning enabled, premium_test_enabled`,
    [req.user.sub, input.enabled, input.premiumTestEnabled],
  );
  res.json({
    notificationsEnabled: rows[0].enabled,
    premiumEnabled: rows[0].premium_test_enabled === true,
    premiumTestEnabled: rows[0].premium_test_enabled === true,
  });
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
  await ensurePassengerColumns();
  const { rows } = await pool.query(
    `select d.id, d.status, d.reason, d.created_at, d.severity, d.broadcast_to_all, d.alert_category,
            d.official_zone, d.affected_routes,
            coalesce(d.route_external_id, d.route_id::text) as route_external_id,
            coalesce(d.route_name, r.name, f.route_name, 'Ligne scolaire') as route_name
     from delays d
     left join passenger_favorite_routes f on f.user_id=$1 and f.route_external_id=coalesce(d.route_external_id, d.route_id::text)
     left join passenger_hidden_alerts h on h.user_id=$1 and h.delay_id=d.id
     left join school_routes r on r.id=d.route_id
     where d.created_at > now() - interval '7 days'
       and (
         d.broadcast_to_all=true
         or f.user_id is not null
         or (
           d.alert_category='sector_safety'
           and exists (
             select 1
             from passenger_favorite_routes sf
             where sf.user_id=$1
               and exists (
                 select 1
                 from unnest(d.affected_routes) kw
                 where lower(sf.route_external_id) like '%' || lower(kw) || '%'
                    or lower(sf.route_name) like '%' || lower(kw) || '%'
                    or lower(sf.route_short_name) like '%' || lower(kw) || '%'
               )
           )
         )
       )
       and h.delay_id is null
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
      message: row.alert_category === 'suspension'
        ? `TRANSPORT SCOLAIRE SUSPENDU\n${row.route_name}\nSuite a ${row.reason}, la circulation des transports scolaires est interdite aujourd'hui.`
        : row.alert_category === 'sector_safety'
          ? `TRANSPORT SCOLAIRE SUSPENDU\nSecteur : ${row.official_zone ?? row.route_name}\nSuite a ${row.reason}, la circulation des transports scolaires est interdite aujourd'hui.`
        : row.broadcast_to_all
          ? `Alerte prioritaire transport scolaire : ${row.status} - ${row.reason}.`
        : `${row.route_name} : ${row.status} suite a ${row.reason}.`,
      createdAt: row.created_at,
      severity: row.severity ?? (row.status.toLowerCase().includes('retard') ? 'warning' : 'info'),
      category: row.alert_category ?? 'route',
      broadcastToAll: row.broadcast_to_all,
    })),
  });
});

router.delete('/alerts/:alertId', async (req, res) => {
  await ensurePassengerColumns();
  const alertId = Number.parseInt(req.params.alertId, 10);
  if (!Number.isInteger(alertId) || alertId <= 0) {
    return res.status(400).json({ error: 'invalid_alert_id' });
  }
  await pool.query(
    `insert into passenger_hidden_alerts(user_id, delay_id)
     values ($1, $2)
     on conflict (user_id, delay_id) do nothing`,
    [req.user.sub, alertId],
  );
  res.status(204).end();
});

router.delete('/alerts', async (req, res) => {
  await ensurePassengerColumns();
  await pool.query(
    `insert into passenger_hidden_alerts(user_id, delay_id)
     select $1, d.id
     from delays d
     left join passenger_favorite_routes f on f.user_id=$1 and f.route_external_id=coalesce(d.route_external_id, d.route_id::text)
     where d.created_at > now() - interval '7 days'
       and (
         d.broadcast_to_all=true
         or f.user_id is not null
         or (
           d.alert_category='sector_safety'
           and exists (
             select 1
             from passenger_favorite_routes sf
             where sf.user_id=$1
               and exists (
                 select 1
                 from unnest(d.affected_routes) kw
                 where lower(sf.route_external_id) like '%' || lower(kw) || '%'
                    or lower(sf.route_name) like '%' || lower(kw) || '%'
                    or lower(sf.route_short_name) like '%' || lower(kw) || '%'
               )
           )
         )
       )
     on conflict (user_id, delay_id) do nothing`,
    [req.user.sub],
  );
  res.status(204).end();
});

router.get('/absences', async (req, res) => {
  await ensurePassengerColumns();
  const { rows } = await pool.query(
    `select route_external_id as "routeExternalId", route_name as "routeName", absent, service_date as "serviceDate", updated_at as "updatedAt"
     from passenger_absence_reports
     where user_id=$1 and service_date >= current_date - interval '7 days'
     order by service_date desc, updated_at desc`,
    [req.user.sub],
  );
  res.json({ absences: rows });
});

router.post('/absence', async (req, res) => {
  await ensurePassengerColumns();
  const input = absenceSchema.parse(req.body);
  const { rows } = await pool.query(
    `insert into passenger_absence_reports(user_id, route_external_id, route_name, service_date, absent, updated_at)
     values ($1, $2, $3, current_date, $4, now())
     on conflict (user_id, route_external_id, service_date)
     do update set route_name=excluded.route_name, absent=excluded.absent, updated_at=now()
     returning route_external_id as "routeExternalId", route_name as "routeName", absent, service_date as "serviceDate", updated_at as "updatedAt"`,
    [req.user.sub, input.routeExternalId, input.routeName, input.absent],
  );
  res.status(201).json(rows[0]);
});

router.get('/live-positions', async (req, res) => {
  const settings = await getPassengerSettings(req.user.sub);
  const { rows: favorites } = await pool.query(
    `select route_external_id, route_name, route_short_name
     from passenger_favorite_routes
     where user_id=$1
     order by created_at desc`,
    [req.user.sub],
  );

  if (!settings.premiumEnabled) {
    return res.json({
      premium: false,
      positions: [],
      message: 'Suivi GPS du car disponible avec Premium',
    });
  }

  if (favorites.length === 0) {
    return res.json({ premium: true, positions: [] });
  }

  const routeIds = favorites.map((favorite) => favorite.route_external_id);
  const { rows } = await pool.query(
    `select distinct on (r.route_external_id)
            r.id as "runId",
            r.route_external_id as "routeExternalId",
            r.route_name as "routeName",
            g.latitude::float as latitude,
            g.longitude::float as longitude,
            g.speed::float as speed,
            g.recorded_at as "recordedAt",
            extract(epoch from (now() - g.recorded_at))::int as "ageSeconds"
     from daily_runs r
     join gps_positions g
       on g.route_external_id=r.route_external_id
      and g.driver_id=r.driver_id
      and g.recorded_at >= r.started_at
     where r.service_date=current_date
       and r.status in ('started','paused')
       and r.route_external_id = any($1::text[])
     order by r.route_external_id, g.recorded_at desc`,
    [routeIds],
  );

  res.json({
    premium: true,
    positions: rows.map((row) => ({
      ...row,
      etaMinutes: row.ageSeconds <= 180 ? 8 : null,
      approaching: row.ageSeconds <= 180,
    })),
  });
});

export default router;
