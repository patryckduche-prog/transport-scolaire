import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';
import { sendCriticalSafetyNotification, sendDelayNotification } from '../services/fcm.service.js';
import { classifyTransportAlert } from '../services/route-alerts.service.js';

const router = Router();
const schema = z.object({
  routeId: z.string(),
  routeName: z.string().optional(),
  status: z.string(),
  reason: z.string(),
});

function shortDelayStatus(status) {
  const match = String(status).match(/(\d+)/);
  if (match) return `${match[1]} min`;
  if (String(status).toLowerCase().includes('superieur')) return '+30 min';
  return status;
}

function compactRouteName(routeName, routeId) {
  const raw = String(routeName ?? routeId);
  return raw.replace(/^(\d+[A-Z0-9]*)\s*-\s*/i, 'Ligne $1 - ');
}

function notificationMessage({ routeName, routeId, status, reason, critical }) {
  if (critical === 'suspension') {
    return `${compactRouteName(routeName, routeId)}\nTRANSPORT SCOLAIRE SUSPENDU\nMotif : ${reason}`;
  }
  if (critical) {
    return `ALERTE PRIORITAIRE\n${status}\nMotif : ${reason}`;
  }
  return `${compactRouteName(routeName, routeId)}\nRETARD : ${shortDelayStatus(status)}\nMotif : ${reason}`;
}

router.post('/', requireAuth(['driver']), async (req, res) => {
  const input = schema.parse(req.body);
  const uuidRoute = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.routeId);
  const alert = classifyTransportAlert(input.status, input.reason);
  const routeExternalId = uuidRoute ? input.routeId : input.routeId;
  const duplicate = await pool.query(
    `select *
     from delays
     where driver_id=$1
       and coalesce(route_external_id, route_id::text)=$2
       and lower(status)=lower($3)
       and lower(reason)=lower($4)
       and created_at > now() - interval '10 minutes'
     order by created_at desc
     limit 1`,
    [req.user.sub, routeExternalId, input.status, input.reason],
  );
  if (duplicate.rows.length > 0) {
    return res.status(200).json({ ...duplicate.rows[0], duplicate: true });
  }

  const { rows } = await pool.query(
    `insert into delays(route_id, route_external_id, route_name, driver_id, status, reason, severity, broadcast_to_all, alert_category)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     returning *`,
    [
      uuidRoute ? input.routeId : null,
      routeExternalId,
      input.routeName ?? null,
      req.user.sub,
      input.status,
      input.reason,
      alert.severity,
      alert.broadcastToAll,
      alert.category,
    ],
  );
  const body = alert.category === 'suspension'
    ? `Transport scolaire suspendu sur ${input.routeName ?? input.routeId} : ${input.reason}.`
    : alert.broadcastToAll
      ? `Alerte prioritaire transport scolaire : ${input.status} - ${input.reason}.`
      : `Bus ${input.routeName ?? input.routeId} : ${input.status} suite a ${input.reason}.`;
  const visibleMessage = notificationMessage({
    routeName: input.routeName,
    routeId: input.routeId,
    status: input.status,
    reason: input.reason,
    critical: alert.category === 'suspension' ? 'suspension' : alert.broadcastToAll,
  });
  if (alert.broadcastToAll) {
    await sendCriticalSafetyNotification(body, {
      alertId: rows[0].id,
      title: alert.category === 'suspension'
        ? 'TRANSPORT SCOLAIRE SUSPENDU'
        : undefined,
      category: alert.category,
      routeId: input.routeId,
      message: visibleMessage,
    });
  } else {
    await sendDelayNotification(input.routeId, body, {
      alertId: rows[0].id,
      severity: alert.severity,
      category: alert.category,
      message: visibleMessage,
    });
  }
  res.status(201).json(rows[0]);
});

export default router;
