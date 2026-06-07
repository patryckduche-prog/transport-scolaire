import fs from 'fs';
import { env } from '../config/env.js';

const schoolDataUrl = new URL('../../data/school_sector_routes.json', import.meta.url);
const generatedSchoolDataUrl = new URL('../../data/school_sector_routes.generated.json', import.meta.url);
const coordinatesUrl = new URL('../../data/coach_stop_coordinates.json', import.meta.url);
const coachRulesUrl = new URL('../../data/coach_route_rules.json', import.meta.url);

function readJson(url, fallback) {
  try {
    return JSON.parse(fs.readFileSync(url, 'utf8'));
  } catch {
    return fallback;
  }
}

function readSchoolRoutes() {
  const manual = readJson(schoolDataUrl, { routes: [] });
  const generated = fs.existsSync(generatedSchoolDataUrl)
    ? readJson(generatedSchoolDataUrl, { routes: [] })
    : { routes: [] };
  const routesById = new Map();
  for (const route of generated.routes ?? []) routesById.set(route.id, route);
  for (const route of manual.routes ?? []) routesById.set(route.id, route);
  return [...routesById.values()];
}

function readRules(routeId) {
  const data = readJson(coachRulesUrl, { default: {}, routes: {} });
  return {
    ...(data.default ?? {}),
    ...(data.routes?.[routeId] ?? {}),
    vehicleProfile: {
      ...(data.default?.vehicleProfile ?? {}),
      ...(data.routes?.[routeId]?.vehicleProfile ?? {}),
    },
    rules: [...(data.default?.rules ?? []), ...(data.routes?.[routeId]?.rules ?? [])],
  };
}

function stopsWithCoordinates(routeId, route) {
  const coordinateData = readJson(coordinatesUrl, {});
  const routeCoordinates = coordinateData[routeId]?.stops ?? [];
  return route.stops.map((name, index) => {
    const sequence = index + 1;
    const coordinates = routeCoordinates.find((item) => Number(item.sequence) === sequence);
    return {
      id: `${routeId}-${sequence}`,
      sequence,
      name,
      latitude: coordinates?.latitude ?? null,
      longitude: coordinates?.longitude ?? null,
    };
  });
}

function osrmInstruction(step) {
  const maneuver = step.maneuver ?? {};
  const road = step.name ? ` sur ${step.name}` : '';
  const modifiers = {
    left: 'a gauche',
    right: 'a droite',
    slight_left: 'legerement a gauche',
    slight_right: 'legerement a droite',
    sharp_left: 'fortement a gauche',
    sharp_right: 'fortement a droite',
    straight: 'tout droit',
    uturn: 'faites demi-tour',
  };
  const modifier = maneuver.modifier ? ` ${modifiers[maneuver.modifier] ?? maneuver.modifier}` : '';
  const distance = Math.round(step.distance ?? 0);
  switch (maneuver.type) {
    case 'depart':
      return `Depart${road}`;
    case 'arrive':
      return 'Vous arrivez a destination';
    case 'turn':
      return `Tournez${modifier}${road} dans ${distance} metres`;
    case 'roundabout':
    case 'rotary':
      return `Prenez le rond-point${road} dans ${distance} metres`;
    case 'merge':
      return `Inserez-vous${road} dans ${distance} metres`;
    case 'new name':
      return `Continuez${road}`;
    default:
      return `Continuez${road} pendant ${distance} metres`;
  }
}

async function routeWithOsrm(stops) {
  const coordinates = stops
    .filter((stop) => stop.latitude != null && stop.longitude != null)
    .map((stop) => `${stop.longitude},${stop.latitude}`)
    .join(';');
  if (!coordinates) throw new Error('missing_coordinates');

  const url = new URL(`/route/v1/driving/${coordinates}`, env.osrmBaseUrl);
  url.searchParams.set('overview', 'full');
  url.searchParams.set('geometries', 'geojson');
  url.searchParams.set('steps', 'true');
  url.searchParams.set('annotations', 'true');
  const response = await fetch(url, { headers: { accept: 'application/json' } });
  if (!response.ok) throw new Error(`osrm_${response.status}`);
  const data = await response.json();
  const route = data.routes?.[0];
  if (!route) throw new Error('osrm_no_route');
  const steps = route.legs
    .flatMap((leg) => leg.steps ?? [])
    .map((step, index) => ({
      index: index + 1,
      distanceMeters: Math.round(step.distance ?? 0),
      durationSeconds: Math.round(step.duration ?? 0),
      name: step.name ?? '',
      instruction: osrmInstruction(step),
    }));
  return {
    provider: 'osrm',
    profile: 'driving',
    distanceMeters: Math.round(route.distance ?? 0),
    durationSeconds: Math.round(route.duration ?? 0),
    geometry: (route.geometry?.coordinates ?? []).map(([longitude, latitude]) => ({ latitude, longitude })),
    steps,
  };
}

async function routeWithGraphhopper(stops) {
  if (!env.graphhopperApiKey) throw new Error('graphhopper_api_key_missing');
  const url = new URL('/route', env.graphhopperBaseUrl);
  url.searchParams.set('key', env.graphhopperApiKey);
  const body = {
    profile: 'truck',
    points: stops
      .filter((stop) => stop.latitude != null && stop.longitude != null)
      .map((stop) => [stop.longitude, stop.latitude]),
    points_encoded: false,
    instructions: true,
    locale: 'fr',
    custom_model: {
      priority: [
        { if: 'road_class == MOTORWAY', multiply_by: '0.7' },
        { if: 'max_width < 2.55', multiply_by: '0' },
        { if: 'max_height < 3.5', multiply_by: '0' }
      ]
    }
  };
  const response = await fetch(url, {
    method: 'POST',
    headers: { accept: 'application/json', 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`graphhopper_${response.status}`);
  const data = await response.json();
  const path = data.paths?.[0];
  if (!path) throw new Error('graphhopper_no_route');
  return {
    provider: 'graphhopper',
    profile: 'truck-custom',
    distanceMeters: Math.round(path.distance ?? 0),
    durationSeconds: Math.round((path.time ?? 0) / 1000),
    geometry: (path.points?.coordinates ?? []).map(([longitude, latitude]) => ({ latitude, longitude })),
    steps: (path.instructions ?? []).map((step, index) => ({
      index: index + 1,
      distanceMeters: Math.round(step.distance ?? 0),
      durationSeconds: Math.round((step.time ?? 0) / 1000),
      name: step.street_name ?? '',
      instruction: step.text ?? 'Continuez',
    })),
  };
}

function fallbackRoute(stops) {
  return {
    provider: 'reference-stops',
    profile: 'coach-reference',
    distanceMeters: null,
    durationSeconds: null,
    geometry: stops
      .filter((stop) => stop.latitude != null && stop.longitude != null)
      .map((stop) => ({ latitude: stop.latitude, longitude: stop.longitude })),
    steps: stops.map((stop) => ({
      index: stop.sequence,
      distanceMeters: null,
      durationSeconds: null,
      name: stop.name,
      instruction: `Rejoindre l'arret ${stop.sequence} : ${stop.name}`,
    })),
  };
}

export async function buildCoachNavigation(routeId) {
  const route = readSchoolRoutes().find((item) => item.id === routeId);
  if (!route) return null;
  const stops = stopsWithCoordinates(routeId, route);
  const rules = readRules(routeId);
  let navigation;
  try {
    navigation = env.routingProvider === 'graphhopper'
      ? await routeWithGraphhopper(stops)
      : await routeWithOsrm(stops);
  } catch (error) {
    navigation = { ...fallbackRoute(stops), error: error.message };
  }

  return {
    routeId,
    routeName: route.longName,
    shortName: route.shortName,
    generatedAt: new Date().toISOString(),
    vehicleProfile: rules.vehicleProfile,
    safetyNotice: rules.safetyNotice,
    externalNavigationNotice: rules.externalNavigationNotice,
    rules: rules.rules ?? [],
    stops,
    ...navigation,
    voicePrompts: [
      `Navigation car scolaire ${route.shortName} chargee.`,
      'Suivez le circuit officiel valide par l exploitation.',
      ...navigation.steps.slice(0, 8).map((step) => step.instruction),
    ],
  };
}
