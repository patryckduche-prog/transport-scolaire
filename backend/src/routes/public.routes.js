import { Router } from 'express';
import { pool } from '../db/pool.js';

const router = Router();

router.get('/alerts', async (_, res) => {
  const { rows } = await pool.query(`
    select d.id, d.status, d.reason, d.created_at, d.severity, d.broadcast_to_all, d.alert_category,
           coalesce(d.route_name, r.name, d.route_external_id) as route_name
    from delays d
    left join school_routes r on r.id = d.route_id
    where d.created_at > now() - interval '24 hours'
    order by d.broadcast_to_all desc, d.created_at desc
    limit 10`);

  if (rows.length === 0) {
    return res.json({
      alerts: [
        {
          id: 'demo-ready',
          routeName: 'Reseau scolaire',
          status: 'Aucune alerte active',
          reason: 'Trafic normal',
          message: 'Aucune perturbation declaree sur les dernieres 24 heures.',
          createdAt: new Date().toISOString(),
          severity: 'info',
          category: 'route',
          broadcastToAll: false,
        },
      ],
    });
  }

  res.json({
    alerts: rows.map((row) => ({
      id: row.id,
      routeName: row.route_name ?? 'Ligne scolaire',
      status: row.status,
      reason: row.reason,
      message: row.broadcast_to_all
        ? `Alerte prioritaire transport scolaire : ${row.status} - ${row.reason}.`
        : `${row.route_name ?? 'Bus scolaire'} : ${row.status} suite a ${row.reason}.`,
      createdAt: row.created_at,
      severity: row.severity ?? (row.status.toLowerCase().includes('retard') ? 'warning' : 'info'),
      category: row.alert_category ?? 'route',
      broadcastToAll: row.broadcast_to_all,
    })),
  });
});

export default router;
