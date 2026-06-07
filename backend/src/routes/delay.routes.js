import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';
import { sendCriticalSafetyNotification, sendDelayNotification } from '../services/fcm.service.js';

const router = Router();
const schema = z.object({
  routeId: z.string(),
  routeName: z.string().optional(),
  status: z.string(),
  reason: z.string(),
});

function classifyAlert(status, reason) {
  const text = `${status} ${reason}`.toLowerCase();
  const criticalWords = [
    'prefecture',
    'prefet',
    'interdiction',
    'circulation interdite',
    'chimique',
    'nucleaire',
    'orsec',
    'evacuation',
    'confinement',
    'alerte rouge',
  ];
  if (criticalWords.some((word) => text.includes(word))) {
    return { severity: 'critical', broadcastToAll: true, category: 'safety' };
  }
  return { severity: 'warning', broadcastToAll: false, category: 'route' };
}

router.post('/', requireAuth(['driver']), async (req, res) => {
  const input = schema.parse(req.body);
  const uuidRoute = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.routeId);
  const alert = classifyAlert(input.status, input.reason);
  const { rows } = await pool.query(
    `insert into delays(route_id, route_external_id, route_name, driver_id, status, reason, severity, broadcast_to_all, alert_category)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     returning *`,
    [
      uuidRoute ? input.routeId : null,
      uuidRoute ? input.routeId : input.routeId,
      input.routeName ?? null,
      req.user.sub,
      input.status,
      input.reason,
      alert.severity,
      alert.broadcastToAll,
      alert.category,
    ],
  );
  const body = alert.broadcastToAll
    ? `Alerte prioritaire transport scolaire : ${input.status} - ${input.reason}.`
    : `Bus ${input.routeName ?? input.routeId} : ${input.status} suite a ${input.reason}.`;
  if (alert.broadcastToAll) {
    await sendCriticalSafetyNotification(body);
  } else {
    await sendDelayNotification(input.routeId, body);
  }
  res.status(201).json(rows[0]);
});

export default router;
