-- HUËLLIK ALERTA: city metadata, public community alerts and automatic lost-pet sync.
alter table public.pets
  add column if not exists city text,
  add column if not exists area text;

create table if not exists public.pet_alerts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  pet_id uuid references public.pets(id) on delete set null,
  alert_type text not null check (alert_type in ('lost','found','sighting')),
  pet_name text not null check (char_length(trim(pet_name)) between 1 and 80),
  species text not null default 'dog' check (species in ('dog','cat','other')),
  city text not null check (char_length(trim(city)) between 2 and 100),
  area text,
  description text,
  photo_url text,
  last_seen_at timestamptz,
  pet_public_id uuid,
  status text not null default 'active' check (status in ('active','reunited','closed')),
  expires_at timestamptz not null default (now() + interval '30 days'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists pet_alerts_one_linked_pet_idx
  on public.pet_alerts(pet_id) where pet_id is not null;
create index if not exists pet_alerts_city_status_created_idx
  on public.pet_alerts(lower(city), status, created_at desc);

alter table public.pet_alerts enable row level security;

drop policy if exists "Public can view active pet alerts" on public.pet_alerts;
create policy "Public can view active pet alerts"
on public.pet_alerts for select to anon, authenticated
using (status = 'active' and expires_at > now());

drop policy if exists "Owners can view their pet alerts" on public.pet_alerts;
create policy "Owners can view their pet alerts"
on public.pet_alerts for select to authenticated
using (owner_id = (select auth.uid()));

drop policy if exists "Authenticated users can create pet alerts" on public.pet_alerts;
create policy "Authenticated users can create pet alerts"
on public.pet_alerts for insert to authenticated
with check (owner_id = (select auth.uid()));

drop policy if exists "Owners can update their pet alerts" on public.pet_alerts;
create policy "Owners can update their pet alerts"
on public.pet_alerts for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

drop policy if exists "Owners can delete their pet alerts" on public.pet_alerts;
create policy "Owners can delete their pet alerts"
on public.pet_alerts for delete to authenticated
using (owner_id = (select auth.uid()));

grant select on public.pet_alerts to anon, authenticated;
grant insert, update, delete on public.pet_alerts to authenticated;

-- These trigger functions use a fixed search_path and are not callable as API RPCs.
create or replace function public.validate_pet_alert_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare linked_pet public.pets%rowtype;
begin
  if auth.uid() is null or new.owner_id is distinct from auth.uid() then
    raise exception 'No tienes permiso para publicar este aviso.';
  end if;
  if new.pet_id is not null then
    select * into linked_pet from public.pets where id = new.pet_id;
    if not found or linked_pet.owner_id is distinct from auth.uid() then
      raise exception 'Solo puedes vincular mascotas de tu propia cuenta.';
    end if;
    new.pet_public_id := linked_pet.public_id;
    if new.alert_type = 'lost' then
      new.pet_name := linked_pet.name;
      new.species := linked_pet.species;
      new.photo_url := linked_pet.photo_url;
    end if;
  else
    new.pet_public_id := null;
  end if;
  return new;
end;
$$;

drop trigger if exists validate_pet_alert_owner_trigger on public.pet_alerts;
create trigger validate_pet_alert_owner_trigger
before insert or update of owner_id, pet_id, pet_public_id
on public.pet_alerts
for each row execute function public.validate_pet_alert_owner();

create or replace function public.sync_pet_lost_alert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.is_lost is true and nullif(trim(coalesce(new.city,'')), '') is not null then
    insert into public.pet_alerts
      (owner_id, pet_id, alert_type, pet_name, species, city, area, description, photo_url, pet_public_id, status, expires_at)
    values
      (new.owner_id, new.id, 'lost', new.name, new.species, trim(new.city), nullif(trim(new.area), ''),
       nullif(trim(coalesce(new.public_description, new.color, '')), ''), new.photo_url, new.public_id, 'active', now() + interval '30 days')
    on conflict (pet_id) where pet_id is not null
    do update set
      owner_id = excluded.owner_id,
      pet_name = excluded.pet_name,
      species = excluded.species,
      city = excluded.city,
      area = excluded.area,
      description = excluded.description,
      photo_url = excluded.photo_url,
      pet_public_id = excluded.pet_public_id,
      status = 'active',
      expires_at = now() + interval '30 days',
      updated_at = now();
  elsif tg_op = 'UPDATE' and old.is_lost is true and new.is_lost is false then
    update public.pet_alerts
       set status = 'reunited', updated_at = now()
     where pet_id = new.id and alert_type = 'lost' and status = 'active';
  end if;
  return new;
end;
$$;

drop trigger if exists sync_pet_lost_alert_trigger on public.pets;
create trigger sync_pet_lost_alert_trigger
after insert or update of is_lost, city, area, name, species, public_description, color, photo_url
on public.pets
for each row execute function public.sync_pet_lost_alert();

revoke all on function public.validate_pet_alert_owner() from public, anon, authenticated;
revoke all on function public.sync_pet_lost_alert() from public, anon, authenticated;
