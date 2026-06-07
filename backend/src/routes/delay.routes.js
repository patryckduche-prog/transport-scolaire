import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';
import { sendCriticalSafetyNotification, sendDelayNotification, sendSectorSafetyNotification } from '../services/fcm.service.js';
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
  if (critical === 'sector_safety') {
    return `TRANSPORT SCOLAIRE SUSPENDU\nSecteur : ${routeName ?? routeId}\nMotif : ${reason}`;
  }
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

  const sectorKeywords = Array.isArray(req.user?.sector?.keywords) && req.user.sector.keywords.length > 0
    ? req.user.sector.keywords
    : [input.routeName ?? input.routeId];
  const sectorName = req.user?.sector?.name ?? input.routeName ?? input.routeId;
  const officialSource = ['suspension', 'sector_safety'].includes(alert.category) ? 'manual_validated' : 'manual';
  const officialText = `${input.status} - ${input.reason}`;
  const officialZone = alert.category === 'sector_safety' ? sectorName : input.routeName ?? input.routeId;
  const { rows } = await pool.query(
    `insert into delays(
       route_id, route_external_id, route_name, driver_id, status, reason,
       severity, broadcast_to_all, alert_category,
       official_source, official_date, official_text, official_zone,
       affected_routes, validated_by, validated_at
     )
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, now(), $11, $12, $13::text[], $14, now())
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
      officialSource,
      officialText,
      officialZone,
      alert.category === 'sector_safety' ? sectorKeywords : [routeExternalId],
      req.user.sub,
    ],
  );
  const body = alert.category === 'sector_safety'
    ? `Transport scolaire suspendu sur le secteur ${sectorName} : ${input.reason}.`
    : alert.category === 'suspension'
    ? `Transport scolaire suspendu sur ${input.routeName ?? input.routeId} : ${input.reason}.`
    : alert.broadcastToAll
      ? `Alerte prioritaire transport scolaire : ${input.status} - ${input.reason}.`
      : `Bus ${input.routeName ?? input.routeId} : ${input.status} suite a ${input.reason}.`;
  const visibleMessage = notificationMessage({
    routeName: alert.category === 'sector_safety' ? sectorName : input.routeName,
    routeId: input.routeId,
    status: input.status,
    reason: input.reason,
    critical: alert.category === 'sector_safety' ? 'sector_safety' : alert.category === 'suspension' ? 'suspension' : alert.broadcastToAll,
  });
  if (alert.broadcastToAll) {
    await sendCriticalSafetyNotification(body, {
      alertId: rows[0].id,
      title: alert.category === 'suspension'
        ? 'TRANSPORT SCOLAIRE SUSPENDU'
        : undefined,
      category: alert.category,
      routeId: input.routeId,
      excludeUserId: req.user.sub,
      message: visibleMessage,
    });
  } else if (alert.category === 'sector_safety') {
    await sendSectorSafetyNotification(sectorKeywords, body, {
      alertId: rows[0].id,
      title: 'TRANSPORT SCOLAIRE SUSPENDU',
      severity: alert.severity,
      category: alert.category,
      routeId: input.routeId,
      sectorName,
      excludeUserId: req.user.sub,
      message: visibleMessage,
    });
  } else if (alert.category === 'suspension') {
    await sendDelayNotification(input.routeId, body, {
      alertId: rows[0].id,
      title: 'TRANSPORT SCOLAIRE SUSPENDU',
      severity: alert.severity,
      category: alert.category,
      excludeUserId: req.user.sub,
      message: visibleMessage,
    });
  } else {
    await sendDelayNotification(input.routeId, body, {
      alertId: rows[0].id,
      severity: alert.severity,
      category: alert.category,
      excludeUserId: req.user.sub,
      message: visibleMessage,
    });
  }
  res.status(201).json(rows[0]);
});

export default router;
