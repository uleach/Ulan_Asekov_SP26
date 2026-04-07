-- SQL_DDL_Ulan_Asekov_HW.sql
-- topic: car sharing

-- create database car_sharing_db;
-- then connect to it and run the rest

-- ddl order matters because child tables cannot reference parent tables
-- if parent table does not exist yet, postgres will throw foreign key / relation does not exist errors

create schema if not exists car_sharing;
set search_path to car_sharing;

-- if FK is missing, child rows can point to records that do not exist
-- for example trip can point to user_id that is not in users table
-- then joins and reports become unreliable

-- wrong data type risks:
-- text instead of numeric -> cannot safely calculate prices or distance
-- integer instead of timestamp -> date logic breaks
-- too short varchar -> important values like vin or email may get cut
-- float instead of numeric -> price rounding problems


create table if not exists users (
    user_id integer generated always as identity primary key,
    name varchar(100) not null, -- prevents empty user name
    email varchar(255) not null unique, -- prevents duplicate accounts with same email
    phone varchar(20),
    created_at timestamp not null default now(),
    check (created_at >= timestamp '2000-01-01 00:00:00') -- prevents unrealistic old dates
);

create table if not exists vehicle_types (
    vehicle_type_id integer generated always as identity primary key,
    type_name varchar(50) not null unique, -- prevents duplicate type names
    price_per_minute numeric(6,2) not null,
    price_per_km numeric(6,2) not null,
    check (price_per_minute >= 0), -- prevents negative tariff
    check (price_per_km >= 0) -- prevents negative tariff
);

create table if not exists locations (
    location_id integer generated always as identity primary key,
    city varchar(100) not null,
    latitude numeric(9,6),
    longitude numeric(9,6),
    check (latitude is null or latitude between -90 and 90), -- prevents impossible coordinates
    check (longitude is null or longitude between -180 and 180)
);

create table if not exists reservation_statuses (
    reservation_status_id integer generated always as identity primary key,
    status_name varchar(30) not null unique,
    check (status_name in ('active', 'completed', 'cancelled')) -- only allowed values
);

create table if not exists vehicle_statuses (
    vehicle_status_id integer generated always as identity primary key,
    status_name varchar(30) not null unique,
    check (status_name in ('available', 'reserved', 'in_use', 'maintenance'))
);

create table if not exists employees (
    employee_id integer generated always as identity primary key,
    name varchar(100) not null,
    role varchar(50),
    hire_date date,
    check (role is null or role in ('mechanic', 'inspector', 'manager')), -- only allowed roles
    check (hire_date is null or hire_date > date '2000-01-01')
);

create table if not exists vehicles (
    vehicle_id integer generated always as identity primary key,
    vehicle_type_id integer not null,
    vin varchar(50) not null unique,
    license_plate varchar(20) not null unique,
    created_at timestamp not null default now(),
    check (created_at >= timestamp '2000-01-01 00:00:00'),
    foreign key (vehicle_type_id) references vehicle_types(vehicle_type_id)
);

create table if not exists reservations (
    reservation_id integer generated always as identity primary key,
    user_id integer not null,
    vehicle_id integer not null,
    reservation_status_id integer not null,
    reserved_from timestamp not null,
    reserved_until timestamp not null,
    check (reserved_from > timestamp '2000-01-01 00:00:00'),
    check (reserved_until >= reserved_from), -- prevents reservation end before start
    foreign key (user_id) references users(user_id),
    foreign key (vehicle_id) references vehicles(vehicle_id),
    foreign key (reservation_status_id) references reservation_statuses(reservation_status_id)
);

create table if not exists vehicle_status_history (
    status_history_id integer generated always as identity primary key,
    vehicle_id integer not null,
    vehicle_status_id integer not null,
    start_time timestamp not null,
    end_time timestamp,
    check (start_time > timestamp '2000-01-01 00:00:00'),
    check (end_time is null or end_time >= start_time),
    foreign key (vehicle_id) references vehicles(vehicle_id),
    foreign key (vehicle_status_id) references vehicle_statuses(vehicle_status_id)
);

create table if not exists trips (
    trip_id integer generated always as identity primary key,
    reservation_id integer not null unique, -- one reservation -> max one trip
    user_id integer not null,
    vehicle_id integer not null,
    start_location_id integer,
    end_location_id integer,
    start_time timestamp not null,
    end_time timestamp,
    distance_km numeric(6,2),
    cost numeric(8,2),
    check (start_time > timestamp '2000-01-01 00:00:00'),
    check (end_time is null or end_time >= start_time),
    check (distance_km is null or distance_km >= 0), -- prevents negative measured value
    check (cost is null or cost >= 0),
    foreign key (reservation_id) references reservations(reservation_id),
    foreign key (user_id) references users(user_id),
    foreign key (vehicle_id) references vehicles(vehicle_id),
    foreign key (start_location_id) references locations(location_id),
    foreign key (end_location_id) references locations(location_id)
);

create table if not exists maintenance_records (
    maintenance_id integer generated always as identity primary key,
    vehicle_id integer not null,
    employee_id integer not null,
    maintenance_date timestamp not null,
    notes text,
    check (maintenance_date > timestamp '2000-01-01 00:00:00'),
    foreign key (vehicle_id) references vehicles(vehicle_id),
    foreign key (employee_id) references employees(employee_id)
);

create table if not exists inspections (
    inspection_id integer generated always as identity primary key,
    vehicle_id integer not null,
    employee_id integer not null,
    inspection_date timestamp not null,
    result varchar(50),
    notes text,
    check (inspection_date > timestamp '2000-01-01 00:00:00'),
    foreign key (vehicle_id) references vehicles(vehicle_id),
    foreign key (employee_id) references employees(employee_id)
);

create table if not exists payments (
    payment_id integer generated always as identity primary key,
    trip_id integer not null unique,
    user_id integer not null,
    amount numeric(8,2) not null,
    payment_time timestamp not null,
    check (amount >= 0), -- prevents negative payment
    check (payment_time > timestamp '2000-01-01 00:00:00'),
    foreign key (trip_id) references trips(trip_id),
    foreign key (user_id) references users(user_id)
);

create table if not exists ratings (
    rating_id integer generated always as identity primary key,
    trip_id integer not null unique,
    user_id integer not null,
    rating_value integer not null,
    comment text,
    created_at timestamp not null default now(),
    check (rating_value between 1 and 5), -- prevents invalid rating like 0 or 9
    check (created_at > timestamp '2000-01-01 00:00:00'),
    foreign key (trip_id) references trips(trip_id),
    foreign key (user_id) references users(user_id)
);

-- a few indexes for joins / filters
create index if not exists idx_vehicles_vehicle_type_id on vehicles(vehicle_type_id);
create index if not exists idx_reservations_user_id on reservations(user_id);
create index if not exists idx_reservations_vehicle_id on reservations(vehicle_id);
create index if not exists idx_trips_user_id on trips(user_id);
create index if not exists idx_trips_vehicle_id on trips(vehicle_id);
create index if not exists idx_vehicle_status_history_vehicle_id on vehicle_status_history(vehicle_id);
create index if not exists idx_maintenance_records_vehicle_id on maintenance_records(vehicle_id);
create index if not exists idx_inspections_vehicle_id on inspections(vehicle_id);



-- sample data
-- using on conflict do nothing or where not exists so rerunning does not create duplicates
-- consistency is preserved by inserting parent tables first and then using existing keys from them


insert into users (name, email, phone) values
('Aibek Osmonov', 'aibek@mail.com', '+996700111111'),
('Aizada Sadykova', 'aizada@mail.com', '+996700222222')
on conflict do nothing;

insert into users (name, email, phone) values
('Bekzat Isakov', 'bekzat@mail.com', '+996700333333'),
('Nurgul Tursunova', 'nurgul@mail.com', '+996700444444')
on conflict do nothing;


insert into vehicle_types (type_name, price_per_minute, price_per_km) values
('Economy', 0.30, 0.50),
('Comfort', 0.40, 0.65)
on conflict do nothing;

insert into vehicle_types (type_name, price_per_minute, price_per_km) values
('Premium', 0.55, 0.80),
('Electro', 0.45, 0.60)
on conflict do nothing;


insert into locations (city, latitude, longitude)
select 'Bishkek', 42.874600, 74.569800
where not exists (
    select 1 from locations
    where city = 'Bishkek' and latitude = 42.874600 and longitude = 74.569800
);

insert into locations (city, latitude, longitude)
select 'Bishkek', 42.880000, 74.590000
where not exists (
    select 1 from locations
    where city = 'Bishkek' and latitude = 42.880000 and longitude = 74.590000
);

insert into locations (city, latitude, longitude)
select 'Osh', 40.528300, 72.798500
where not exists (
    select 1 from locations
    where city = 'Osh' and latitude = 40.528300 and longitude = 72.798500
);

insert into locations (city, latitude, longitude)
select 'Osh', 40.520000, 72.790000
where not exists (
    select 1 from locations
    where city = 'Osh' and latitude = 40.520000 and longitude = 72.790000
);


insert into reservation_statuses (status_name) values
('active'),
('completed'),
('cancelled')
on conflict do nothing;


insert into vehicle_statuses (status_name) values
('available'),
('reserved'),
('in_use'),
('maintenance')
on conflict do nothing;


insert into employees (name, role, hire_date) values
('Ulanbek Joldoshov', 'mechanic', '2024-01-15'),
('Meerim Asanova', 'inspector', '2024-02-01')
on conflict do nothing;

insert into employees (name, role, hire_date) values
('Kubanychbek Saparov', 'manager', '2024-03-10'),
('Nazira Abdyldaeva', 'mechanic', '2024-04-05')
on conflict do nothing;


insert into vehicles (vehicle_type_id, vin, license_plate)
select vt.vehicle_type_id, 'KGZVIN001', '01KG123ABC'
from vehicle_types vt
where vt.type_name = 'Economy'
on conflict do nothing;

insert into vehicles (vehicle_type_id, vin, license_plate)
select vt.vehicle_type_id, 'KGZVIN002', '01KG456DEF'
from vehicle_types vt
where vt.type_name = 'Comfort'
on conflict do nothing;

insert into vehicles (vehicle_type_id, vin, license_plate)
select vt.vehicle_type_id, 'KGZVIN003', '02KG789GHI'
from vehicle_types vt
where vt.type_name = 'Premium'
on conflict do nothing;

insert into vehicles (vehicle_type_id, vin, license_plate)
select vt.vehicle_type_id, 'KGZVIN004', '02KG999JKL'
from vehicle_types vt
where vt.type_name = 'Electro'
on conflict do nothing;


insert into reservations (user_id, vehicle_id, reservation_status_id, reserved_from, reserved_until)
select u.user_id, v.vehicle_id, rs.reservation_status_id,
       timestamp '2026-03-03 08:00:00', timestamp '2026-03-03 08:30:00'
from users u, vehicles v, reservation_statuses rs
where u.email = 'aibek@mail.com'
  and v.vin = 'KGZVIN001'
  and rs.status_name = 'completed'
  and not exists (
      select 1 from reservations r
      where r.user_id = u.user_id
        and r.vehicle_id = v.vehicle_id
        and r.reserved_from = timestamp '2026-03-03 08:00:00'
  );

insert into reservations (user_id, vehicle_id, reservation_status_id, reserved_from, reserved_until)
select u.user_id, v.vehicle_id, rs.reservation_status_id,
       timestamp '2026-03-03 09:00:00', timestamp '2026-03-03 09:30:00'
from users u, vehicles v, reservation_statuses rs
where u.email = 'aizada@mail.com'
  and v.vin = 'KGZVIN002'
  and rs.status_name = 'completed'
  and not exists (
      select 1 from reservations r
      where r.user_id = u.user_id
        and r.vehicle_id = v.vehicle_id
        and r.reserved_from = timestamp '2026-03-03 09:00:00'
  );

insert into reservations (user_id, vehicle_id, reservation_status_id, reserved_from, reserved_until)
select u.user_id, v.vehicle_id, rs.reservation_status_id,
       timestamp '2026-03-04 10:00:00', timestamp '2026-03-04 10:20:00'
from users u, vehicles v, reservation_statuses rs
where u.email = 'bekzat@mail.com'
  and v.vin = 'KGZVIN003'
  and rs.status_name = 'active'
  and not exists (
      select 1 from reservations r
      where r.user_id = u.user_id
        and r.vehicle_id = v.vehicle_id
        and r.reserved_from = timestamp '2026-03-04 10:00:00'
  );

insert into reservations (user_id, vehicle_id, reservation_status_id, reserved_from, reserved_until)
select u.user_id, v.vehicle_id, rs.reservation_status_id,
       timestamp '2026-03-04 11:00:00', timestamp '2026-03-04 11:25:00'
from users u, vehicles v, reservation_statuses rs
where u.email = 'nurgul@mail.com'
  and v.vin = 'KGZVIN004'
  and rs.status_name = 'cancelled'
  and not exists (
      select 1 from reservations r
      where r.user_id = u.user_id
        and r.vehicle_id = v.vehicle_id
        and r.reserved_from = timestamp '2026-03-04 11:00:00'
  );


insert into vehicle_status_history (vehicle_id, vehicle_status_id, start_time, end_time)
select v.vehicle_id, s.vehicle_status_id,
       timestamp '2026-03-01 09:00:00', timestamp '2026-03-03 08:00:00'
from vehicles v, vehicle_statuses s
where v.vin = 'KGZVIN001'
  and s.status_name = 'available'
  and not exists (
      select 1 from vehicle_status_history h
      where h.vehicle_id = v.vehicle_id
        and h.vehicle_status_id = s.vehicle_status_id
        and h.start_time = timestamp '2026-03-01 09:00:00'
  );

insert into vehicle_status_history (vehicle_id, vehicle_status_id, start_time, end_time)
select v.vehicle_id, s.vehicle_status_id,
       timestamp '2026-03-03 08:00:00', timestamp '2026-03-03 08:35:00'
from vehicles v, vehicle_statuses s
where v.vin = 'KGZVIN001'
  and s.status_name = 'in_use'
  and not exists (
      select 1 from vehicle_status_history h
      where h.vehicle_id = v.vehicle_id
        and h.vehicle_status_id = s.vehicle_status_id
        and h.start_time = timestamp '2026-03-03 08:00:00'
  );

insert into vehicle_status_history (vehicle_id, vehicle_status_id, start_time, end_time)
select v.vehicle_id, s.vehicle_status_id,
       timestamp '2026-03-01 09:15:00', timestamp '2026-03-03 09:00:00'
from vehicles v, vehicle_statuses s
where v.vin = 'KGZVIN002'
  and s.status_name = 'available'
  and not exists (
      select 1 from vehicle_status_history h
      where h.vehicle_id = v.vehicle_id
        and h.vehicle_status_id = s.vehicle_status_id
        and h.start_time = timestamp '2026-03-01 09:15:00'
  );

insert into vehicle_status_history (vehicle_id, vehicle_status_id, start_time, end_time)
select v.vehicle_id, s.vehicle_status_id,
       timestamp '2026-03-04 10:00:00', timestamp '2026-03-04 12:00:00'
from vehicles v, vehicle_statuses s
where v.vin = 'KGZVIN003'
  and s.status_name = 'maintenance'
  and not exists (
      select 1 from vehicle_status_history h
      where h.vehicle_id = v.vehicle_id
        and h.vehicle_status_id = s.vehicle_status_id
        and h.start_time = timestamp '2026-03-04 10:00:00'
  );


insert into trips (reservation_id, user_id, vehicle_id, start_location_id, end_location_id, start_time, end_time, distance_km, cost)
select r.reservation_id, u.user_id, v.vehicle_id, l1.location_id, l2.location_id,
       timestamp '2026-03-03 08:05:00', timestamp '2026-03-03 08:35:00', 12.50, 10.00
from reservations r, users u, vehicles v, locations l1, locations l2
where u.email = 'aibek@mail.com'
  and v.vin = 'KGZVIN001'
  and r.user_id = u.user_id
  and r.vehicle_id = v.vehicle_id
  and r.reserved_from = timestamp '2026-03-03 08:00:00'
  and l1.city = 'Bishkek' and l1.latitude = 42.874600
  and l2.city = 'Bishkek' and l2.latitude = 42.880000
on conflict do nothing;

insert into trips (reservation_id, user_id, vehicle_id, start_location_id, end_location_id, start_time, end_time, distance_km, cost)
select r.reservation_id, u.user_id, v.vehicle_id, l1.location_id, l2.location_id,
       timestamp '2026-03-03 09:05:00', timestamp '2026-03-03 09:40:00', 8.20, 8.56
from reservations r, users u, vehicles v, locations l1, locations l2
where u.email = 'aizada@mail.com'
  and v.vin = 'KGZVIN002'
  and r.user_id = u.user_id
  and r.vehicle_id = v.vehicle_id
  and r.reserved_from = timestamp '2026-03-03 09:00:00'
  and l1.city = 'Bishkek' and l1.latitude = 42.880000
  and l2.city = 'Bishkek' and l2.latitude = 42.874600
on conflict do nothing;


insert into maintenance_records (vehicle_id, employee_id, maintenance_date, notes)
select v.vehicle_id, e.employee_id, timestamp '2026-03-04 10:00:00', 'oil change'
from vehicles v, employees e
where v.vin = 'KGZVIN001'
  and e.name = 'Ulanbek Joldoshov'
  and not exists (
      select 1 from maintenance_records m
      where m.vehicle_id = v.vehicle_id
        and m.employee_id = e.employee_id
        and m.maintenance_date = timestamp '2026-03-04 10:00:00'
  );

insert into maintenance_records (vehicle_id, employee_id, maintenance_date, notes)
select v.vehicle_id, e.employee_id, timestamp '2026-03-04 11:00:00', 'brake inspection'
from vehicles v, employees e
where v.vin = 'KGZVIN003'
  and e.name = 'Nazira Abdyldaeva'
  and not exists (
      select 1 from maintenance_records m
      where m.vehicle_id = v.vehicle_id
        and m.employee_id = e.employee_id
        and m.maintenance_date = timestamp '2026-03-04 11:00:00'
  );


insert into inspections (vehicle_id, employee_id, inspection_date, result, notes)
select v.vehicle_id, e.employee_id, timestamp '2026-03-04 09:00:00', 'OK', 'no visible issues'
from vehicles v, employees e
where v.vin = 'KGZVIN001'
  and e.name = 'Meerim Asanova'
  and not exists (
      select 1 from inspections i
      where i.vehicle_id = v.vehicle_id
        and i.employee_id = e.employee_id
        and i.inspection_date = timestamp '2026-03-04 09:00:00'
  );

insert into inspections (vehicle_id, employee_id, inspection_date, result, notes)
select v.vehicle_id, e.employee_id, timestamp '2026-03-04 09:30:00', 'OK', 'tires acceptable'
from vehicles v, employees e
where v.vin = 'KGZVIN002'
  and e.name = 'Meerim Asanova'
  and not exists (
      select 1 from inspections i
      where i.vehicle_id = v.vehicle_id
        and i.employee_id = e.employee_id
        and i.inspection_date = timestamp '2026-03-04 09:30:00'
  );


insert into payments (trip_id, user_id, amount, payment_time)
select t.trip_id, u.user_id, 10.00, timestamp '2026-03-03 08:36:00'
from trips t, users u, vehicles v
where t.user_id = u.user_id
  and t.vehicle_id = v.vehicle_id
  and u.email = 'aibek@mail.com'
  and v.vin = 'KGZVIN001'
  and t.start_time = timestamp '2026-03-03 08:05:00'
on conflict do nothing;

insert into payments (trip_id, user_id, amount, payment_time)
select t.trip_id, u.user_id, 8.56, timestamp '2026-03-03 09:41:00'
from trips t, users u, vehicles v
where t.user_id = u.user_id
  and t.vehicle_id = v.vehicle_id
  and u.email = 'aizada@mail.com'
  and v.vin = 'KGZVIN002'
  and t.start_time = timestamp '2026-03-03 09:05:00'
on conflict do nothing;


insert into ratings (trip_id, user_id, rating_value, comment)
select t.trip_id, u.user_id, 5, 'jakshy sapar boldy'
from trips t, users u, vehicles v
where t.user_id = u.user_id
  and t.vehicle_id = v.vehicle_id
  and u.email = 'aibek@mail.com'
  and v.vin = 'KGZVIN001'
  and t.start_time = timestamp '2026-03-03 08:05:00'
on conflict do nothing;

insert into ratings (trip_id, user_id, rating_value, comment)
select t.trip_id, u.user_id, 4, 'bary jakshy, birok az biraz kechikti'
from trips t, users u, vehicles v
where t.user_id = u.user_id
  and t.vehicle_id = v.vehicle_id
  and u.email = 'aizada@mail.com'
  and v.vin = 'KGZVIN002'
  and t.start_time = timestamp '2026-03-03 09:05:00'
on conflict do nothing;



-- now add record_ts to every table using alter table as required
-- default current_date is used for new rows
-- existing rows are updated so record_ts is not null

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'users' and column_name = 'record_ts'
    ) then
        alter table car_sharing.users add column record_ts date;
    end if;
    alter table car_sharing.users alter column record_ts set default current_date;
    update car_sharing.users set record_ts = current_date where record_ts is null;
    alter table car_sharing.users alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'vehicle_types' and column_name = 'record_ts'
    ) then
        alter table car_sharing.vehicle_types add column record_ts date;
    end if;
    alter table car_sharing.vehicle_types alter column record_ts set default current_date;
    update car_sharing.vehicle_types set record_ts = current_date where record_ts is null;
    alter table car_sharing.vehicle_types alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'locations' and column_name = 'record_ts'
    ) then
        alter table car_sharing.locations add column record_ts date;
    end if;
    alter table car_sharing.locations alter column record_ts set default current_date;
    update car_sharing.locations set record_ts = current_date where record_ts is null;
    alter table car_sharing.locations alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'reservation_statuses' and column_name = 'record_ts'
    ) then
        alter table car_sharing.reservation_statuses add column record_ts date;
    end if;
    alter table car_sharing.reservation_statuses alter column record_ts set default current_date;
    update car_sharing.reservation_statuses set record_ts = current_date where record_ts is null;
    alter table car_sharing.reservation_statuses alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'vehicle_statuses' and column_name = 'record_ts'
    ) then
        alter table car_sharing.vehicle_statuses add column record_ts date;
    end if;
    alter table car_sharing.vehicle_statuses alter column record_ts set default current_date;
    update car_sharing.vehicle_statuses set record_ts = current_date where record_ts is null;
    alter table car_sharing.vehicle_statuses alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'employees' and column_name = 'record_ts'
    ) then
        alter table car_sharing.employees add column record_ts date;
    end if;
    alter table car_sharing.employees alter column record_ts set default current_date;
    update car_sharing.employees set record_ts = current_date where record_ts is null;
    alter table car_sharing.employees alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'vehicles' and column_name = 'record_ts'
    ) then
        alter table car_sharing.vehicles add column record_ts date;
    end if;
    alter table car_sharing.vehicles alter column record_ts set default current_date;
    update car_sharing.vehicles set record_ts = current_date where record_ts is null;
    alter table car_sharing.vehicles alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'reservations' and column_name = 'record_ts'
    ) then
        alter table car_sharing.reservations add column record_ts date;
    end if;
    alter table car_sharing.reservations alter column record_ts set default current_date;
    update car_sharing.reservations set record_ts = current_date where record_ts is null;
    alter table car_sharing.reservations alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'vehicle_status_history' and column_name = 'record_ts'
    ) then
        alter table car_sharing.vehicle_status_history add column record_ts date;
    end if;
    alter table car_sharing.vehicle_status_history alter column record_ts set default current_date;
    update car_sharing.vehicle_status_history set record_ts = current_date where record_ts is null;
    alter table car_sharing.vehicle_status_history alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'trips' and column_name = 'record_ts'
    ) then
        alter table car_sharing.trips add column record_ts date;
    end if;
    alter table car_sharing.trips alter column record_ts set default current_date;
    update car_sharing.trips set record_ts = current_date where record_ts is null;
    alter table car_sharing.trips alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'maintenance_records' and column_name = 'record_ts'
    ) then
        alter table car_sharing.maintenance_records add column record_ts date;
    end if;
    alter table car_sharing.maintenance_records alter column record_ts set default current_date;
    update car_sharing.maintenance_records set record_ts = current_date where record_ts is null;
    alter table car_sharing.maintenance_records alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'inspections' and column_name = 'record_ts'
    ) then
        alter table car_sharing.inspections add column record_ts date;
    end if;
    alter table car_sharing.inspections alter column record_ts set default current_date;
    update car_sharing.inspections set record_ts = current_date where record_ts is null;
    alter table car_sharing.inspections alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'payments' and column_name = 'record_ts'
    ) then
        alter table car_sharing.payments add column record_ts date;
    end if;
    alter table car_sharing.payments alter column record_ts set default current_date;
    update car_sharing.payments set record_ts = current_date where record_ts is null;
    alter table car_sharing.payments alter column record_ts set not null;
end $$;

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'car_sharing' and table_name = 'ratings' and column_name = 'record_ts'
    ) then
        alter table car_sharing.ratings add column record_ts date;
    end if;
    alter table car_sharing.ratings alter column record_ts set default current_date;
    update car_sharing.ratings set record_ts = current_date where record_ts is null;
    alter table car_sharing.ratings alter column record_ts set not null;
end $$;


-- quick check that record_ts is filled
select 'users' as table_name, count(*) as null_record_ts from users where record_ts is null
union all
select 'vehicle_types', count(*) from vehicle_types where record_ts is null
union all
select 'locations', count(*) from locations where record_ts is null
union all
select 'reservation_statuses', count(*) from reservation_statuses where record_ts is null
union all
select 'vehicle_statuses', count(*) from vehicle_statuses where record_ts is null
union all
select 'employees', count(*) from employees where record_ts is null
union all
select 'vehicles', count(*) from vehicles where record_ts is null
union all
select 'reservations', count(*) from reservations where record_ts is null
union all
select 'vehicle_status_history', count(*) from vehicle_status_history where record_ts is null
union all
select 'trips', count(*) from trips where record_ts is null
union all
select 'maintenance_records', count(*) from maintenance_records where record_ts is null
union all
select 'inspections', count(*) from inspections where record_ts is null
union all
select 'payments', count(*) from payments where record_ts is null
union all
select 'ratings', count(*) from ratings where record_ts is null
order by table_name;
