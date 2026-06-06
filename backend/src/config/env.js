import dotenv from 'dotenv';
dotenv.config();

export const env = {
  port: Number(process.env.PORT ?? 3000),
  databaseUrl: process.env.DATABASE_URL ?? 'postgres://bus:bus@localhost:5432/bus_scolaire_connect',
  databaseSsl: process.env.DATABASE_SSL === 'true',
  jwtSecret: process.env.JWT_SECRET ?? 'dev-secret',
  fcmServiceAccountPath: process.env.FCM_SERVICE_ACCOUNT_PATH,
};
