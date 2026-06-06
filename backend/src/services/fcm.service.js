import admin from 'firebase-admin';
import fs from 'fs';
import { pool } from '../db/pool.js';
import { env } from '../config/env.js';

let ready = false;

try {
  if (env.fcmServiceAccountPath) {
    if (fs.existsSync(env.fcmServiceAccountPath)) {
      const serviceAccount = JSON.parse(fs.readFileSync(env.fcmServiceAccountPath, 'utf8'));
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
      ready = true;
      console.log('FCM enabled');
    } else {
      console.warn(`FCM disabled: service account not found at ${env.fcmServiceAccountPath}`);
    }
  }
} catch (error) {
  console.warn('FCM disabled:', error.message);
}

export async function sendDelayNotification(routeId, body) {
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
    android: { priority: 'high', notification: { sound: 'default' } },
  });
}
