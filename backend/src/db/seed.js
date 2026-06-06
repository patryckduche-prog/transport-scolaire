import bcrypt from 'bcryptjs';
import { pool } from './pool.js';

const passwordHash = await bcrypt.hash('demo1234', 10);
const driverCodeHash = await bcrypt.hash('AUMALE-2026', 10);
await pool.query(`
insert into users(id, name, email, password_hash, role) values
('00000000-0000-0000-0000-000000000001','Conducteur Demo','conducteur@demo.local',$1,'driver'),
('00000000-0000-0000-0000-000000000002','Parent Demo','parent@demo.local',$1,'parent'),
('00000000-0000-0000-0000-000000000003','Entreprise Demo','entreprise@demo.local',$1,'company'),
('00000000-0000-0000-0000-000000000004','Region Demo','region@demo.local',$1,'region')
on conflict (email) do update set password_hash=excluded.password_hash`, [passwordHash]);
await pool.query(`
insert into driver_access_codes(id, code_hash, driver_id, label, sector_name, sector_keywords, active) values
('40000000-0000-0000-0000-000000000001',$1,'00000000-0000-0000-0000-000000000001','Code secteur Aumale','Aumale',ARRAY['aumale'],true)
on conflict (id) do update set code_hash=excluded.code_hash, label=excluded.label, sector_name=excluded.sector_name, sector_keywords=excluded.sector_keywords, active=true`, [driverCodeHash]);
await pool.query(`
insert into vehicles(id, plate_number, driver_id, capacity, company, status) values
('10000000-0000-0000-0000-000000000001','AB-123-CD','00000000-0000-0000-0000-000000000001',55,'Transports Demo','operationnel') on conflict do nothing;
insert into school_routes(id, name, vehicle_id) values
('20000000-0000-0000-0000-000000000001','Ligne 12','10000000-0000-0000-0000-000000000001') on conflict do nothing;
insert into stops(id, name, latitude, longitude) values
('30000000-0000-0000-0000-000000000001','College Jean Moulin',48.856600,2.352200),
('30000000-0000-0000-0000-000000000002','Place de la Mairie',48.861000,2.340000),
('30000000-0000-0000-0000-000000000003','Route des Pins',48.870000,2.330000) on conflict do nothing;
insert into route_stops(route_id, stop_id, sequence, scheduled_time) values
('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',1,'07:42'),
('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002',2,'07:51'),
('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003',3,'08:03') on conflict do nothing;
insert into user_routes(user_id, route_id) values
('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001') on conflict do nothing;`);
await pool.query(`
insert into passenger_notification_settings(user_id, enabled) values
('00000000-0000-0000-0000-000000000002', true) on conflict (user_id) do nothing;`);
await pool.end();
console.log('Database seeded. Sector driver code: AUMALE-2026. Admin password: demo1234');
