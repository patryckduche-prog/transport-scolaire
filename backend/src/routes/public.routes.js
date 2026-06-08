import { Router } from 'express';
import { pool } from '../db/pool.js';

const router = Router();
const weatherCache = new Map();
const weatherCacheTtlMs = 10 * 60 * 1000;

function weatherFromCode(code) {
  if (code === 0) return { label: 'Ciel clair', icon: 'sun', state: 'normal' };
  if ([1, 2].includes(code)) return { label: 'Eclaircies', icon: 'partly_cloudy', state: 'normal' };
  if (code === 3) return { label: 'Nuageux', icon: 'cloud', state: 'normal' };
  if ([45, 48].includes(code)) return { label: 'Brouillard', icon: 'fog', state: 'fog' };
  if ([51, 53, 55, 61, 63, 65, 80, 81, 82].includes(code)) {
    return { label: 'Pluie', icon: 'rain', state: 'rain' };
  }
  if ([56, 57, 66, 67].includes(code)) return { label: 'Verglas possible', icon: 'ice', state: 'ice' };
  if ([71, 73, 75, 77, 85, 86].includes(code)) return { label: 'Neige', icon: 'snow', state: 'snow' };
  if ([95, 96, 99].includes(code)) return { label: 'Orage', icon: 'storm', state: 'rain' };
  return { label: 'Meteo locale', icon: 'weather', state: 'normal' };
}

function numberQuery(value, fallback) {
  const parsed = Number.parseFloat(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

router.get('/alerts', async (_, res) => {
  const { rows } = await pool.query(`
    select d.id, d.status, d.reason, d.created_at, d.severity, d.broadcast_to_all, d.alert_category,
           coalesce(d.route_name, r.name, d.route_external_id) as route_name
    from delays d
    left join school_routes r on r.id = d.route_id
    where d.created_at > now() - interval '24 hours'
      and d.broadcast_to_all=true
    order by d.broadcast_to_all desc, d.created_at desc
    limit 10`);

  if (rows.length === 0) {
    return res.json({
      alerts: [
        {
          id: 'demo-ready',
          routeName: 'Securite transport',
          status: 'Aucune alerte securite active',
          reason: 'Aucune interdiction generale',
          message: 'Aucune alerte prioritaire generale declaree.',
          createdAt: new Date().toISOString(),
          severity: 'info',
          category: 'safety',
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
      message: row.alert_category === 'suspension'
        ? `TRANSPORT SCOLAIRE SUSPENDU\n${row.route_name ?? 'Ligne scolaire'}\nSuite a ${row.reason}, la circulation des transports scolaires est interdite aujourd'hui.`
        : row.broadcast_to_all
          ? `Alerte prioritaire transport scolaire : ${row.status} - ${row.reason}.`
        : `${row.route_name ?? 'Bus scolaire'} : ${row.status} suite a ${row.reason}.`,
      createdAt: row.created_at,
      severity: row.severity ?? (row.status.toLowerCase().includes('retard') ? 'warning' : 'info'),
      category: row.alert_category ?? 'route',
      broadcastToAll: row.broadcast_to_all,
    })),
  });
});

router.get('/weather', async (req, res) => {
  const latitude = numberQuery(req.query.lat, 49.77);
  const longitude = numberQuery(req.query.lon, 1.75);
  const cacheKey = `${latitude.toFixed(2)},${longitude.toFixed(2)}`;
  const cached = weatherCache.get(cacheKey);
  if (cached && Date.now() - cached.cachedAt < weatherCacheTtlMs) {
    return res.json(cached.payload);
  }

  try {
    const url = new URL('https://api.open-meteo.com/v1/forecast');
    url.searchParams.set('latitude', latitude.toString());
    url.searchParams.set('longitude', longitude.toString());
    url.searchParams.set(
      'current',
      'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,is_day',
    );
    url.searchParams.set('timezone', 'Europe/Paris');
    const response = await fetch(url);
    if (!response.ok) throw new Error(`weather_${response.status}`);
    const data = await response.json();
    const current = data.current ?? {};
    const code = Number(current.weather_code ?? 0);
    const mapped = weatherFromCode(code);
    const payload = {
      source: 'open-meteo',
      location: {
        name: 'Aumale / Normandie',
        latitude,
        longitude,
      },
      temperatureC: current.temperature_2m ?? null,
      humidity: current.relative_humidity_2m ?? null,
      windKmh: current.wind_speed_10m ?? null,
      weatherCode: code,
      weatherLabel: mapped.label,
      weatherIcon: mapped.icon,
      weatherState: mapped.state,
      isDay: current.is_day === 1,
      updatedAt: current.time ?? new Date().toISOString(),
    };
    weatherCache.set(cacheKey, { cachedAt: Date.now(), payload });
    return res.json(payload);
  } catch (_) {
    return res.status(503).json({
      error: 'weather_unavailable',
      message: 'Meteo locale indisponible pour le moment.',
    });
  }
});

export default router;
