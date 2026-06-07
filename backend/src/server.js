import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import http from 'http';
import morgan from 'morgan';
import path from 'path';
import { fileURLToPath } from 'url';
import { env } from './config/env.js';
import authRoutes from './routes/auth.routes.js';
import delayRoutes from './routes/delay.routes.js';
import driverCodeRoutes from './routes/driver-code.routes.js';
import gpsRoutes from './routes/gps.routes.js';
import presenceRoutes from './routes/presence.routes.js';
import reportRoutes from './routes/report.routes.js';
import routeRoutes from './routes/route.routes.js';
import vehicleRoutes from './routes/vehicle.routes.js';
import nomadRoutes from './routes/nomad.routes.js';
import passengerRoutes from './routes/passenger.routes.js';
import publicRoutes from './routes/public.routes.js';
import runRoutes from './routes/run.routes.js';
import { attachRealtime } from './services/realtime.service.js';

const publicDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../public');
const apkPath = path.join(publicDir, 'download', 'bus-scolaire-connect.apk');
const appVersion = '1.0.15';
const app = express();
app.set('trust proxy', true);
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(morgan('dev'));
app.use('/code-generator', express.static(path.join(publicDir, 'code-generator')));
app.use('/driver-mode-preview', express.static(path.join(publicDir, 'driver-mode-preview')));
app.use('/gps-preview', express.static(path.join(publicDir, 'gps-preview')));
app.get('/download/bus-scolaire-connect.apk', (_, res) => {
  res.setHeader('Content-Type', 'application/vnd.android.package-archive');
  res.setHeader('Content-Disposition', 'attachment; filename="bus-scolaire-connect.apk"');
  res.download(apkPath, 'bus-scolaire-connect.apk');
});
app.use('/download', express.static(path.join(publicDir, 'download')));
app.get('/', (_, res) =>
  res.json({
    ok: true,
    name: 'Bus Scolaire Connect API',
    message: 'Backend operationnel. Utilisez /health ou les endpoints /api.',
    endpoints: [
      '/health',
      '/api/public/alerts',
      '/api/auth/login',
      '/code-generator/',
      '/api/routes',
      '/api/nomad/routes?highlighted=true',
      '/api/reports/dashboard',
      '/api/runs/start',
      '/ws',
    ],
  }),
);
app.get('/health', (_, res) => res.json({ ok: true, name: 'Bus Scolaire Connect API' }));
app.get('/api/app-version', (req, res) => {
  const host = req.get('host');
  const local = host?.startsWith('localhost') || host?.startsWith('127.0.0.1');
  const protocol = local ? req.protocol : 'https';
  const baseUrl = `${protocol}://${host}`;
  res.json({
    latestVersion: appVersion,
    minSupportedVersion: '1.0.9',
    apkUrl: `${baseUrl}/download/bus-scolaire-connect.apk`,
    downloadPageUrl: `${baseUrl}/download/`,
    title: 'Nouvelle version disponible',
    message: 'Une nouvelle version de Bus Scolaire Connect est prete. Telechargez-la pour profiter des dernieres corrections.',
    mandatory: false,
  });
});
app.use('/api/auth', authRoutes);
app.use('/api/driver-codes', driverCodeRoutes);
app.use('/api/public', publicRoutes);
app.use('/api/routes', routeRoutes);
app.use('/api/delays', delayRoutes);
app.use('/api/presence', presenceRoutes);
app.use('/api/gps', gpsRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/vehicles', vehicleRoutes);
app.use('/api/nomad', nomadRoutes);
app.use('/api/passenger', passengerRoutes);
app.use('/api/runs', runRoutes);

const server = http.createServer(app);
attachRealtime(server);
server.listen(env.port, () => console.log(`API running on http://localhost:${env.port}`));
