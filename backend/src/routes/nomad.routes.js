import fs from 'fs';
import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
const dataUrl = new URL('../../data/nomad_routes.json', import.meta.url);
const schoolDataUrl = new URL('../../data/school_sector_routes.json', import.meta.url);
const generatedSchoolDataUrl = new URL('../../data/school_sector_routes.generated.json', import.meta.url);

function readNomadData() {
  return JSON.parse(fs.readFileSync(dataUrl, 'utf8'));
}

function readSchoolData() {
  const manual = JSON.parse(fs.readFileSync(schoolDataUrl, 'utf8'));
  const generated = fs.existsSync(generatedSchoolDataUrl)
    ? JSON.parse(fs.readFileSync(generatedSchoolDataUrl, 'utf8'))
    : { routes: [] };
  const routesById = new Map();
  for (const route of generated.routes ?? []) routesById.set(route.id, route);
  for (const route of manual.routes ?? []) routesById.set(route.id, route);
  return {
    source: `${manual.source} + ${generated.source ?? 'import PDF'}`,
    routes: [...routesById.values()],
  };
}

function toNomadShape(route) {
  return {
    id: route.id,
    shortName: route.shortName,
    longName: route.longName,
    color: '0F6F78',
    textColor: 'FFFFFF',
    type: route.type,
    source: 'Fiche horaires scolaires Nomad',
    tripCount: route.tripCount ?? 1,
    stopCount: route.stops.length,
    highlighted: true,
    schoolSector: true,
    sourceFile: route.sourceFile,
    sectorKeywords: route.sectorKeywords ?? [],
    stops: route.stops.map((name, index) => ({
      id: `${route.id}-${index + 1}`,
      code: '',
      name,
      latitude: null,
      longitude: null,
      arrivalTime: '',
      departureTime: '',
      sequence: index + 1,
    })),
  };
}

function normalize(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

function routeMatchesKeywords(route, keywords) {
  if (!keywords || keywords.length === 0) return true;
  const routeText = route.sourceFile
    ? normalize(`${route.shortName} ${route.longName}`)
    : normalize(`${route.shortName} ${route.longName} ${(route.sectorKeywords ?? []).join(' ')} ${route.stops.map((stop) => stop.name).join(' ')}`);
  return keywords.some((keyword) => routeText.includes(normalize(keyword)));
}

router.use(requireAuth());

router.get('/routes', (req, res) => {
  const query = String(req.query.q ?? '').toLowerCase();
  const highlighted = req.query.highlighted === 'true';
  const data = readNomadData();
  const schoolData = readSchoolData();
  let routes = [...schoolData.routes.map(toNomadShape), ...data.routes];
  const sector = req.user?.role === 'driver' ? req.user.sector : null;
  const sectorKeywords = Array.isArray(sector?.keywords) ? sector.keywords : [];

  if (sectorKeywords.length > 0) {
    routes = routes.filter((route) => routeMatchesKeywords(route, sectorKeywords));
  }

  if (highlighted) {
    routes = routes.filter((route) => route.highlighted);
  }

  if (query) {
    routes = routes.filter((route) => {
      const routeText = `${route.shortName} ${route.longName}`.toLowerCase();
      const stopText = route.stops.map((stop) => stop.name).join(' ').toLowerCase();
      return routeText.includes(query) || stopText.includes(query);
    });
  }

  res.json({
    summary: {
      ...data.summary,
      schoolRouteCount: schoolData.routes.length,
      routeCount: data.summary.routeCount + schoolData.routes.length,
    },
    routes: routes.map((route) => ({
      id: route.id,
      shortName: route.shortName,
      longName: route.longName,
      color: route.color,
      textColor: route.textColor,
      type: route.type,
      schoolSector: route.schoolSector ?? false,
      stopCount: route.stopCount,
      tripCount: route.tripCount,
      highlighted: route.highlighted,
      sectorName: sector?.name,
      stopsPreview: route.stops.slice(0, 6),
    })),
    sector: sector ? { name: sector.name, keywords: sectorKeywords } : null,
  });
});

router.get('/routes/:id', (req, res) => {
  const data = readNomadData();
  const schoolData = readSchoolData();
  const schoolRoute = schoolData.routes.map(toNomadShape).find((item) => item.id === req.params.id);
  const route = schoolRoute ?? data.routes.find((item) => item.id === req.params.id);
  if (!route) return res.status(404).json({ error: 'nomad_route_not_found' });
  res.json({
    id: route.id,
    shortName: route.shortName,
    longName: route.longName,
    color: route.color,
    textColor: route.textColor,
    type: route.type,
    schoolSector: route.schoolSector ?? false,
    stopCount: route.stopCount,
    tripCount: route.tripCount,
    highlighted: route.highlighted,
    stopsPreview: route.stops,
    stops: route.stops,
  });
});

export default router;
