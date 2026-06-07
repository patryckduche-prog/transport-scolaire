create extension if not exists pgcrypto;
create table if not exists users (id uuid primary key default gen_random_uuid(), name text not null, email text unique not null, password_hash text not null, role text not null check (role in ('driver','parent','student','company','region')), fcm_token text, created_at timestamptz not null default now());
alter table users add column if not exists guest_device_id text unique;
create table if not exists driver_access_codes (id uuid primary key default gen_random_uuid(), code_hash text not null, driver_id uuid references users(id) on delete cascade, label text not null default 'Code conducteur', sector_name text not null default 'Tous secteurs', sector_keywords text[] not null default '{}', active boolean not null default true, expires_at timestamptz, created_at timestamptz not null default now());
alter table driver_access_codes add column if not exists sector_name text not null default 'Tous secteurs';
alter table driver_access_codes add column if not exists sector_keywords text[] not null default '{}';
create table if not exists login_history (id bigserial primary key, user_id uuid references users(id), ip_address text, created_at timestamptz not null default now());
create table if not exists vehicles (id uuid primary key default gen_random_uuid(), plate_number text unique not null, driver_id uuid references users(id), capacity int not null, company text not null, status text not null default 'operationnel');
create table if not exists school_routes (id uuid primary key default gen_random_uuid(), name text not null, vehicle_id uuid references vehicles(id), planned_polyline text, active boolean not null default true);
create table if not exists stops (id uuid primary key default gen_random_uuid(), name text not null, latitude numeric(9,6) not null, longitude numeric(9,6) not null);
create table if not exists route_stops (route_id uuid references school_routes(id) on delete cascade, stop_id uuid references stops(id) on delete cascade, sequence int not null, scheduled_time time not null, primary key(route_id, stop_id));
create table if not exists user_routes (user_id uuid references users(id) on delete cascade, route_id uuid references school_routes(id) on delete cascade, primary key(user_id, route_id));
create table if not exists passenger_favorite_routes (user_id uuid references users(id) on delete cascade, route_external_id text not null, route_name text not null, route_short_name text not null default '', created_at timestamptz not null default now(), primary key(user_id, route_external_id));
create table if not exists passenger_notification_settings (user_id uuid primary key references users(id) on delete cascade, enabled boolean not null default true, updated_at timestamptz not null default now());
create table if not exists presences (id bigserial primary key, user_id uuid references users(id), route_id uuid references school_routes(id), stop_id uuid references stops(id), service_date date not null, present boolean not null, updated_at timestamptz not null default now(), unique(user_id, route_id, stop_id, service_date));
create table if not exists delays (id bigserial primary key, route_id uuid references school_routes(id), driver_id uuid references users(id), status text not null, reason text not null, created_at timestamptz not null default now());
alter table delays add column if not exists route_external_id text;
alter table delays add column if not exists route_name text;
create table if not exists gps_positions (id bigserial primary key, route_id uuid references school_routes(id), driver_id uuid references users(id), latitude numeric(9,6) not null, longitude numeric(9,6) not null, speed numeric(6,2) not null default 0, recorded_at timestamptz not null default now());
alter table gps_positions add column if not exists route_external_id text;
alter table gps_positions add column if not exists route_name text;
create table if not exists route_signatures (id bigserial primary key, route_id uuid references school_routes(id), driver_id uuid references users(id), signature_base64 text not null, signed_at timestamptz not null default now());

create table if not exists students (
  id uuid primary key default gen_random_uuid(),
  first_name text not null,
  last_name text not null,
  photo_url text,
  guardian_user_id uuid references users(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists student_route_assignments (
  student_id uuid references students(id) on delete cascade,
  route_external_id text not null,
  stop_external_id text not null,
  stop_name text not null,
  direction text not null default 'aller',
  active boolean not null default true,
  primary key(student_id, route_external_id, direction)
);
create table if not exists route_stop_geofences (
  id uuid primary key default gen_random_uuid(),
  route_external_id text not null,
  stop_external_id text not null,
  stop_name text not null,
  latitude numeric(9,6) not null,
  longitude numeric(9,6) not null,
  radius_meters int not null default 50,
  sequence int not null,
  active boolean not null default true,
  unique(route_external_id, stop_external_id)
);
create table if not exists daily_runs (
  id uuid primary key default gen_random_uuid(),
  route_external_id text not null,
  route_name text not null,
  driver_id uuid references users(id) on delete set null,
  vehicle_id uuid references vehicles(id) on delete set null,
  service_date date not null default current_date,
  status text not null default 'started' check (status in ('planned','started','paused','finished','cancelled')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists daily_runs_driver_status_idx on daily_runs(driver_id, status, service_date);
create table if not exists daily_run_stop_events (
  id bigserial primary key,
  run_id uuid references daily_runs(id) on delete cascade,
  stop_external_id text not null,
  stop_name text not null,
  event_type text not null check (event_type in ('approaching','arrived','departed','skipped')),
  distance_meters numeric(8,2),
  event_at timestamptz not null default now(),
  unique(run_id, stop_external_id, event_type)
);
create table if not exists daily_run_student_presence (
  run_id uuid references daily_runs(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  expected boolean not null default true,
  present boolean,
  status text not null default 'expected' check (status in ('expected','present','absent','not_seen')),
  updated_by uuid references users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key(run_id, student_id)
);
create table if not exists run_incidents (
  id bigserial primary key,
  run_id uuid references daily_runs(id) on delete cascade,
  driver_id uuid references users(id) on delete set null,
  type text not null,
  message text not null,
  severity text not null default 'warning',
  created_at timestamptz not null default now()
);
create table if not exists run_finish_checks (
  run_id uuid primary key references daily_runs(id) on delete cascade,
  driver_id uuid references users(id) on delete set null,
  all_students_checked boolean not null default false,
  bus_empty_confirmed boolean not null default false,
  comment text,
  checked_at timestamptz not null default now()
);
