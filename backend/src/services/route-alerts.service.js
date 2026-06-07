export function normalizeAlertText(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

export function classifyTransportAlert(status, reason) {
  const text = normalizeAlertText(`${status} ${reason}`);
  const sectorSafetyWords = [
    'arrete prefectoral',
    'prefectoral',
    'prefecture',
    'prefet',
    'suspension transports scolaires',
    'transport scolaire suspendu',
    'transports scolaires suspendus',
  ];
  if (sectorSafetyWords.some((word) => text.includes(word))) {
    return { severity: 'critical', broadcastToAll: false, category: 'sector_safety', level: 'red' };
  }

  const suspensionWords = [
    'arrete',
    'interdiction',
    'interdit',
    'transports interdits',
    'transport scolaire suspendu',
    'suspension',
    'suspendu',
    'ligne annulee',
    'circulation interdite',
  ];
  if (suspensionWords.some((word) => text.includes(word))) {
    return { severity: 'critical', broadcastToAll: false, category: 'suspension', level: 'red' };
  }

  const criticalSafetyWords = ['chimique', 'nucleaire', 'orsec', 'evacuation', 'confinement', 'alerte rouge'];
  if (criticalSafetyWords.some((word) => text.includes(word))) {
    return { severity: 'critical', broadcastToAll: true, category: 'safety', level: 'red' };
  }

  const warningWords = ['retard 30', 'superieur', 'deviation', 'panne', 'accident', 'route barree', 'verglas', 'neige'];
  if (warningWords.some((word) => text.includes(word))) {
    return { severity: 'warning', broadcastToAll: false, category: 'route', level: 'orange' };
  }

  return { severity: 'info', broadcastToAll: false, category: 'route', level: 'yellow' };
}

function routeDescriptor(route) {
  if (typeof route === 'string') return { id: route, text: route };
  return {
    id: String(route?.id ?? ''),
    text: normalizeAlertText(`${route?.id ?? ''} ${route?.shortName ?? ''} ${route?.longName ?? ''} ${(route?.sectorKeywords ?? []).join(' ')} ${(route?.stops ?? []).map((stop) => stop?.name ?? stop).join(' ')}`),
  };
}

function sectorAlertMatchesRoute(alert, route) {
  const keywords = Array.isArray(alert.affected_routes) ? alert.affected_routes : [];
  const zone = normalizeAlertText(alert.official_zone);
  const text = normalizeAlertText(route.text);
  if (keywords.length === 0 && !zone) return false;
  return [...keywords, zone]
    .filter(Boolean)
    .some((keyword) => text.includes(normalizeAlertText(keyword)));
}

export async function activeRouteSuspensions(pool, routeIds = []) {
  const routes = routeIds.map(routeDescriptor).filter((route) => route.id);
  const ids = [...new Set(routes.map((route) => route.id))];
  if (ids.length === 0) return new Map();

  const { rows: exactRows } = await pool.query(
    `select distinct on (coalesce(route_external_id, route_id::text))
            id, status, reason, created_at, severity, alert_category, official_zone, affected_routes,
            coalesce(route_external_id, route_id::text) as route_external_id,
            coalesce(route_name, route_external_id, route_id::text, 'Ligne scolaire') as route_name
     from delays
     where created_at >= current_date
       and severity='critical'
       and alert_category='suspension'
       and coalesce(route_external_id, route_id::text)=any($1::text[])
     order by coalesce(route_external_id, route_id::text), created_at desc`,
    [ids],
  );

  const { rows: sectorRows } = await pool.query(
    `select id, status, reason, created_at, severity, alert_category, official_zone, affected_routes,
            coalesce(route_external_id, route_id::text) as route_external_id,
            coalesce(route_name, route_external_id, route_id::text, 'Secteur transport scolaire') as route_name
     from delays
     where created_at >= current_date
       and severity='critical'
       and alert_category='sector_safety'
     order by created_at desc`,
  );

  const result = new Map(exactRows.map((row) => [row.route_external_id, row]));
  for (const route of routes) {
    if (result.has(route.id)) continue;
    const sectorAlert = sectorRows.find((alert) => sectorAlertMatchesRoute(alert, route));
    if (sectorAlert) result.set(route.id, { ...sectorAlert, route_external_id: route.id });
  }
  return result;
}

export async function activeRouteSuspension(pool, routeId, routeName = '') {
  const suspensions = await activeRouteSuspensions(pool, [{ id: routeId, longName: routeName }]);
  return suspensions.get(String(routeId)) ?? null;
}

export function suspensionPayload(alert) {
  if (!alert) return null;
  return {
    id: alert.id,
    routeExternalId: alert.route_external_id,
    routeName: alert.route_name,
    status: alert.status,
    reason: alert.reason,
    message: 'TRANSPORTS INTERDITS',
    legalBasis: alert.reason || 'Arrete prefectoral',
    createdAt: alert.created_at,
  };
}
