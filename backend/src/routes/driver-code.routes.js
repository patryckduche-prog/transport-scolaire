import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { pool } from '../db/pool.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();

const createSchema = z.object({
  code: z.string().trim().min(4).max(40),
  driverEmail: z.string().trim().email().default('conducteur@demo.local'),
  label: z.string().trim().min(1).max(120).default('Code conducteur'),
  sectorName: z.string().trim().min(1).max(120).default('Tous secteurs'),
  sectorKeywords: z.array(z.string().trim().min(1).max(80)).default([]),
});

router.use(requireAuth(['company', 'region']));

router.get('/', async (_req, res) => {
  const { rows } = await pool.query(`
    select c.id, c.label, c.sector_name, c.sector_keywords, c.active, c.expires_at, c.created_at, u.name as driver_name, u.email as driver_email
    from driver_access_codes c
    join users u on u.id = c.driver_id
    order by c.created_at desc
    limit 50
  `);
  res.json(rows);
});

router.post('/', async (req, res) => {
  const input = createSchema.parse(req.body);
  const driverResult = await pool.query('select id, name, email from users where email=$1 and role=$2', [input.driverEmail, 'driver']);
  const driver = driverResult.rows[0];
  if (!driver) return res.status(404).json({ error: 'driver_not_found' });

  const codeHash = await bcrypt.hash(input.code, 10);
  const { rows } = await pool.query(
    `insert into driver_access_codes(code_hash, driver_id, label, sector_name, sector_keywords, active)
     values ($1, $2, $3, $4, $5, true)
     returning id, label, sector_name, sector_keywords, active, expires_at, created_at`,
    [codeHash, driver.id, input.label, input.sectorName, input.sectorKeywords.map((item) => item.toLowerCase())],
  );

  res.status(201).json({ ...rows[0], code: input.code, driverName: driver.name, driverEmail: driver.email });
});

router.patch('/:id/disable', async (req, res) => {
  const { rows } = await pool.query('update driver_access_codes set active=false where id=$1 returning id, active', [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: 'code_not_found' });
  res.json(rows[0]);
});

export default router;
