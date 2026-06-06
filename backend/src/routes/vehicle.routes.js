import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';

const router = Router();
router.use(requireAuth(['company', 'region']));
router.get('/', async (_, res) => {
  const { rows } = await pool.query('select * from vehicles order by plate_number');
  res.json(rows);
});
router.post('/', async (req, res) => {
  const { plateNumber, capacity, company, status } = req.body;
  const { rows } = await pool.query('insert into vehicles(plate_number, capacity, company, status) values ($1,$2,$3,$4) returning *', [plateNumber, capacity, company, status]);
  res.status(201).json(rows[0]);
});
export default router;
