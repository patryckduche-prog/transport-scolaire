import fs from 'fs';
import { pool } from './pool.js';
const sql = fs.readFileSync(new URL('../../../database/schema.sql', import.meta.url), 'utf8').replace(/^\uFEFF/, '');
await pool.query(sql);
await pool.end();
console.log('Database migrated');

