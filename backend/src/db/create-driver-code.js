import bcrypt from 'bcryptjs';
import { pool } from './pool.js';

const args = Object.fromEntries(process.argv.slice(2).map((item) => {
  const [key, ...value] = item.replace(/^--/, '').split('=');
  return [key, value.join('=')];
}));

const code = String(args.code ?? '').trim();
const email = String(args.email ?? 'conducteur@demo.local').trim();
const label = String(args.label ?? 'Code conducteur').trim();
const sectorName = String(args.sector ?? 'Tous secteurs').trim();
const sectorKeywords = String(args.keywords ?? '')
  .split(',')
  .map((item) => item.trim().toLowerCase())
  .filter(Boolean);

if (!code) {
  console.error('Usage: npm run driver-code -- --code=MON-CODE --email=conducteur@demo.local');
  process.exit(1);
}

const userResult = await pool.query('select id, role from users where email=$1', [email]);
const user = userResult.rows[0];
if (!user || user.role !== 'driver') {
  console.error(`Conducteur introuvable pour ${email}`);
  process.exit(1);
}

const codeHash = await bcrypt.hash(code, 10);
await pool.query('insert into driver_access_codes(code_hash, driver_id, label, sector_name, sector_keywords, active) values ($1, $2, $3, $4, $5, true)', [
  codeHash,
  user.id,
  label,
  sectorName,
  sectorKeywords,
]);
await pool.end();

console.log(`Code secteur cree pour ${email}: ${code} (${sectorName})`);
