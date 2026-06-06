import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { pool } from '../db/pool.js';
import { env } from '../config/env.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  const { rows } = await pool.query('select id, name, email, role, password_hash from users where email=$1', [email]);
  const user = rows[0];
  if (!user || !(await bcrypt.compare(password, user.password_hash))) return res.status(401).json({ error: 'invalid_credentials' });
  await pool.query('insert into login_history(user_id, ip_address) values ($1, $2)', [user.id, req.ip]);
  const token = jwt.sign({ sub: user.id, role: user.role, email: user.email }, env.jwtSecret, { expiresIn: '12h' });
  res.json({ token, user: { id: user.id, name: user.name, email: user.email, role: user.role } });
});

router.post('/driver-code', async (req, res) => {
  const code = String(req.body?.code ?? '').trim();
  if (!code) return res.status(400).json({ error: 'code_required' });

  const { rows } = await pool.query(`
    select c.id as code_id, c.code_hash, c.sector_name, c.sector_keywords, u.id, u.name, u.email, u.role
    from driver_access_codes c
    join users u on u.id = c.driver_id
    where c.active=true and u.role='driver' and (c.expires_at is null or c.expires_at > now())
  `);

  for (const user of rows) {
    if (await bcrypt.compare(code, user.code_hash)) {
      await pool.query('insert into login_history(user_id, ip_address) values ($1, $2)', [user.id, req.ip]);
      const sector = { name: user.sector_name, keywords: user.sector_keywords ?? [] };
      const token = jwt.sign({ sub: user.id, role: user.role, email: user.email, sector }, env.jwtSecret, { expiresIn: '12h' });
      return res.json({ token, user: { id: user.id, name: user.name, email: user.email, role: user.role, sector } });
    }
  }

  return res.status(401).json({ error: 'invalid_code' });
});

router.post('/guest/passenger', async (req, res) => {
  try {
    const rawDeviceId = String(req.body?.deviceId ?? '').trim();
    const deviceId = rawDeviceId.replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 80);
    if (!deviceId) return res.status(400).json({ error: 'device_id_required' });

    const email = `guest-${deviceId}@bus-scolaire-connect.local`;
    const { rows } = await pool.query(
      `insert into users(name, email, password_hash, role, guest_device_id)
       values ($1, $2, 'guest-access', 'parent', $3)
       on conflict (guest_device_id)
       do update set name=excluded.name
       returning id, name, email, role`,
      ['Acces parent eleve', email, deviceId],
    );
    const user = rows[0];
    await pool.query(
      `insert into passenger_notification_settings(user_id, enabled)
       values ($1, true)
       on conflict (user_id) do nothing`,
      [user.id],
    );
    const token = jwt.sign({ sub: user.id, role: user.role, email: user.email, guest: true }, env.jwtSecret, { expiresIn: '24h' });
    res.json({ token, user });
  } catch (error) {
    console.error('guest passenger access failed', error);
    res.status(500).json({ error: 'guest_access_failed' });
  }
});

router.post('/fcm-token', requireAuth(), async (req, res) => {
  const fcmToken = String(req.body?.fcmToken ?? '').trim();
  if (!fcmToken) return res.status(400).json({ error: 'fcm_token_required' });
  await pool.query('update users set fcm_token=$1 where id=$2', [fcmToken, req.user.sub]);
  res.json({ ok: true });
});
export default router;
