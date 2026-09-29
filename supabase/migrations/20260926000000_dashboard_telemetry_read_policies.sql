-- Prototype dashboard access. The current Flutter login is not Supabase Auth,
-- so the anon role cannot securely distinguish a farmer from an administrator.
-- These policies are deliberately read-only; the Edge Function keeps using the
-- service role for ESP32 writes and is not affected by these grants.

alter table public.iot_devices enable row level security;
alter table public.sensor_readings enable row level security;

revoke insert, update, delete, truncate, references, trigger
  on table public.iot_devices from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.sensor_readings from anon, authenticated;

grant select on table public.iot_devices to anon;
grant select on table public.sensor_readings to anon;

drop policy if exists "dashboard_read_active_devices" on public.iot_devices;
create policy "dashboard_read_active_devices"
on public.iot_devices
for select
to anon
using (active is true);

drop policy if exists "dashboard_read_active_device_readings"
  on public.sensor_readings;
create policy "dashboard_read_active_device_readings"
on public.sensor_readings
for select
to anon
using (
  exists (
    select 1
    from public.iot_devices as device
    where device.device_id = sensor_readings.device_id
      and device.active is true
  )
);
