import admin from 'firebase-admin';
import fs from 'fs';
import { pool } from '../db/pool.js';
import { env } from '../config/env.js';

let ready = false;
let mode = 'disabled';
let lastError = null;

try {
  if (env.fcmServiceAccountJson) {
    const serviceAccount = JSON.parse(env.fcmServiceAccountJson);
    if (serviceAccount.private_key) {
      serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n');
    }
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    ready = true;
    mode = 'env_json';
    console.log('FCM enabled from FIREBASE_SERVICE_ACCOUNT_JSON');
  } else if (env.fcmServiceAccountPath) {
    if (fs.existsSync(env.fcmServiceAccountPath)) {
      const serviceAccount = JSON.parse(fs.readFileSync(env.fcmServiceAccountPath, 'utf8'));
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
      ready = true;
      mode = 'file';
      console.log('FCM enabled');
    } else {
      console.warn(`FCM disabled: service account not found at ${env.fcmServiceAccountPath}`);
    }
  }
} catch (error) {
  lastError = error.message;
  console.warn('FCM disabled:', error.message);
}

export function fcmStatus() {
  return {
    ready,
    mode,
    configured: Boolean(env.fcmServiceAccountJson || env.fcmServiceAccountPath),
    lastError,
  };
}

const visibleAlertTitle = 'ALERTE BUS SCOLAIRE';
const criticalAlertTitle = 'ALERTE SECURITE TRANSPORT';

export async function sendDelayNotification(routeId, body, options = {}) {
  const { rows } = await pool.query(
    `select distinct u.fcm_token
     from users u
     join passenger_favorite_routes f on f.user_id=u.id and f.route_external_id=$1
     left join passenger_notification_settings s on s.user_id=u.id
     where u.role in ('parent', 'student')
       and coalesce(s.enabled, true)=true
       and u.fcm_token is not null
       and ($2::uuid is null or u.id <> $2::uuid)`,
    [routeId, options.excludeUserId ?? null],
  );
  const tokens = rows.map((r) => r.fcm_token);
  if (!ready || tokens.length === 0) {
    console.log('[notification]', body);
    return;
  }
  const title = options.title ?? visibleAlertTitle;
  const message = options.message ?? body;
  await admin.messaging().sendEachForMulticast({
    tokens,
    data: {
      alertId: String(options.alertId ?? ''),
      severity: String(options.severity ?? 'warning'),
      category: String(options.category ?? 'favorite_route'),
      routeId: String(routeId),
      title,
      body: message,
    },
    android: {
      priority: 'high',
      collapseKey: `route-${routeId}`,
      ttl: 1000 * 60 * 60,
    },
  });
}

export async function sendSectorSafetyNotification(sectorKeywords, body, options = {}) {
  const keywords = [...new Set((sectorKeywords ?? [])
    .map((keyword) => String(keyword ?? '').trim().toLowerCase())
    .filter(Boolean))];
  if (keywords.length === 0) return sendDelayNotification(options.routeId ?? '', body, options);

  const patterns = keywords.map((keyword) => `%${keyword}%`);
  const { rows } = await pool.query(
    `select distinct u.fcm_token
     from users u
     join passenger_favorite_routes f on f.user_id=u.id
     left join passenger_notification_settings s on s.user_id=u.id
     where u.role in ('parent', 'student')
       and coalesce(s.enabled, true)=true
       and u.fcm_token is not null
       and ($2::uuid is null or u.id <> $2::uuid)
       and (
         lower(f.route_external_id) like any($1::text[])
         or lower(f.route_name) like any($1::text[])
         or lower(f.route_short_name) like any($1::text[])
       )`,
    [patterns, options.excludeUserId ?? null],
  );
  const tokens = rows.map((r) => r.fcm_token);
  if (!ready || tokens.length === 0) {
    console.log('[sector notification]', body);
    return;
  }
  const title = options.title ?? criticalAlertTitle;
  const message = options.message ?? body;
  await admin.messaging().sendEachForMulticast({
    tokens,
    data: {
      alertId: String(options.alertId ?? ''),
      severity: 'critical',
      category: String(options.category ?? 'sector_safety'),
      routeId: String(options.routeId ?? ''),
      sector: String(options.sectorName ?? ''),
      title,
      body: message,
    },
    android: {
      priority: 'high',
      collapseKey: `sector-${keywords.join('-').slice(0, 48)}`,
      ttl: 1000 * 60 * 60,
    },
  });
}

export async function sendCriticalSafetyNotification(body, options = {}) {
  const roles = options.includeDrivers === true
    ? ['driver', 'parent', 'student']
    : ['parent', 'student'];
  const { rows } = await pool.query(
    `select distinct fcm_token
     from users
     where role = any($1::text[])
       and fcm_token is not null
       and ($2::uuid is null or id <> $2::uuid)`,
    [roles, options.excludeUserId ?? null],
  );
  const tokens = rows.map((r) => r.fcm_token);
  if (!ready || tokens.length === 0) {
    console.log('[critical notification]', body);
    return;
  }
  const title = options.title ?? criticalAlertTitle;
  const message = options.message ?? body;
  await admin.messaging().sendEachForMulticast({
    tokens,
    data: {
      alertId: String(options.alertId ?? ''),
      severity: 'critical',
      category: String(options.category ?? 'safety'),
      routeId: String(options.routeId ?? ''),
      title,
      body: message,
    },
    android: {
      priority: 'high',
      collapseKey: 'critical-transport-safety',
      ttl: 1000 * 60 * 60,
    },
  });
}
