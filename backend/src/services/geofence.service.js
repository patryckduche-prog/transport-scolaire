const EARTH_RADIUS_METERS = 6371000;

export function distanceMeters(a, b) {
  const lat1 = Number(a.latitude) * Math.PI / 180;
  const lat2 = Number(b.latitude) * Math.PI / 180;
  const deltaLat = (Number(b.latitude) - Number(a.latitude)) * Math.PI / 180;
  const deltaLon = (Number(b.longitude) - Number(a.longitude)) * Math.PI / 180;
  const sinLat = Math.sin(deltaLat / 2);
  const sinLon = Math.sin(deltaLon / 2);
  const h = sinLat * sinLat + Math.cos(lat1) * Math.cos(lat2) * sinLon * sinLon;
  return 2 * EARTH_RADIUS_METERS * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

export function detectStopEntry(position, stops) {
  const matches = stops
    .map((stop) => ({
      ...stop,
      distanceMeters: distanceMeters(position, stop),
    }))
    .filter((stop) => stop.distanceMeters <= Number(stop.radius_meters ?? 50))
    .sort((a, b) => a.distanceMeters - b.distanceMeters);
  return matches[0] ?? null;
}
