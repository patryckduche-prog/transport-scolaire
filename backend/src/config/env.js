import dotenv from 'dotenv';
dotenv.config();

export const env = {
  port: Number(process.env.PORT ?? 3000),
  databaseUrl: process.env.DATABASE_URL ?? 'postgres://bus:bus@localhost:5432/bus_scolaire_connect',
  databaseSsl: process.env.DATABASE_SSL === 'true',
  jwtSecret: process.env.JWT_SECRET ?? 'dev-secret',
  fcmServiceAccountPath: process.env.FCM_SERVICE_ACCOUNT_PATH,
  fcmServiceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON,
  routingProvider: process.env.ROUTING_PROVIDER ?? 'osrm',
  osrmBaseUrl: process.env.OSRM_BASE_URL ?? 'https://router.project-osrm.org',
  graphhopperBaseUrl: process.env.GRAPHHOPPER_BASE_URL ?? 'https://graphhopper.com/api/1',
  graphhopperApiKey: process.env.GRAPHHOPPER_API_KEY,
};
