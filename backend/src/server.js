import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
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

const publicDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '../public');
const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(morgan('dev'));
app.use('/code-generator', express.static(path.join(publicDir, 'code-generator')));
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
    ],
  }),
);
app.get('/health', (_, res) => res.json({ ok: true, name: 'Bus Scolaire Connect API' }));
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
app.listen(env.port, () => console.log(`API running on http://localhost:${env.port}`));
