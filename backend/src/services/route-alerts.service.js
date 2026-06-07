export function normalizeAlertText(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

export function classifyTransportAlert(status, reason) {
  const text = normalizeAlertText(`${status} ${reason}`);
  const suspensionWords = [
    'arrete',
    'prefectoral',
    'prefecture',
    'prefet',
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

export async function activeRouteSuspensions(pool, routeIds = []) {
  const ids = [...new Set(routeIds.filter(Boolean).map(String))];
  if (ids.length === 0) return new Map();

  const { rows } = await pool.query(
    `select distinct on (coalesce(route_external_id, route_id::text))
            id, status, reason, created_at, severity, alert_category,
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

  return new Map(rows.map((row) => [row.route_external_id, row]));
}

export async function activeRouteSuspension(pool, routeId) {
  const suspensions = await activeRouteSuspensions(pool, [routeId]);
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
