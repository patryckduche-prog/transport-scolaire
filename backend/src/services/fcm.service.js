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
  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title: 'Alerte bus scolaire', body },
    data: {
      alertId: String(options.alertId ?? ''),
      severity: 'warning',
      category: 'favorite_route',
      routeId: String(routeId),
      title: 'Alerte bus scolaire',
      body,
    },
    android: {
      priority: 'high',
      collapseKey: `route-${routeId}`,
      notification: {
        sound: 'default',
        channelId: 'favorite_route_alerts_v2',
        tag: `route-alert-${options.alertId ?? routeId}`,
        defaultSound: true,
        defaultVibrateTimings: true,
      },
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
  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title: 'Alerte securite transport', body },
    data: {
      alertId: String(options.alertId ?? ''),
      severity: 'critical',
      category: 'safety',
      title: 'Alerte securite transport',
      body,
    },
    android: {
      priority: 'high',
      collapseKey: 'critical-transport-safety',
      notification: {
        sound: 'default',
        channelId: 'critical_transport_safety_v1',
        tag: `critical-alert-${options.alertId ?? 'latest'}`,
        defaultSound: true,
        defaultVibrateTimings: true,
      },
    },
  });
}
