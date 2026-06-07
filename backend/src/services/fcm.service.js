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

const visibleAlertTitle = '\u{1F6A8} ALERTE BUS SCOLAIRE';
const criticalAlertTitle = '\u{1F6A8} ALERTE SECURITE TRANSPORT';

export async function sendDelayNotification(routeId, body, options = {}) {
  const { rows } = await pool.query(
    `select distinct u.fcm_token
     from users u
     join passenger_favorite_routes f on f.user_id=u.id and f.route_external_id=$1
     left join passenger_notification_settings s on s.user_id=u.id
     where coalesce(s.enabled, true)=true and u.fcm_token is not null`,
    [routeId],
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
      severity: 'warning',
      category: 'favorite_route',
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

export async function sendCriticalSafetyNotification(body, options = {}) {
  const { rows } = await pool.query(
    `select distinct fcm_token
     from users
     where role in ('driver', 'parent', 'student')
       and fcm_token is not null`,
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
      category: 'safety',
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
