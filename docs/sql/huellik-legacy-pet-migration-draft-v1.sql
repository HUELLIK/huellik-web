-- HUËLLIK v2 — preflight + one-time legacy data migration draft
-- NOT APPLIED. Run only after verified backup/export and explicit approval.
-- Aborts if petlink already contains pets or contacts. Preserves public tables.
-- public_id is preserved as legacy_public_id, NOT registered as a physical QR/NFC tag.

begin;

alter table petlink.pets
  add column if not exists legacy_public_id uuid,
  add column if not exists sex text,
  add column if not exists birth_date date,
  add column if not exists color text,
  add column if not exists medical_alerts text,
  add column if not exists show_medical_alerts boolean not null default false,
  add column if not exists legacy_species text;

create unique index if not exists petlink_pets_legacy_public_id_uidx
  on petlink.pets (legacy_public_id)
  where legacy_public_id is not null;

create table if not exists petlink.pet_contacts (
  id uuid primary key,
  pet_id uuid not null references petlink.pets(id) on delete cascade,
  name text not null,
  relationship text,
  phone text,
  email text,
  whatsapp_enabled boolean not null default false,
  is_public boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null
);

create index if not exists petlink_pet_contacts_pet_sort_idx
  on petlink.pet_contacts (pet_id, sort_order, created_at);

alter table petlink.pet_contacts enable row level security;
revoke all on table petlink.pet_contacts from anon, authenticated;

do $migration$
declare
  source_pets bigint;
  source_contacts bigint;
  inserted_pets bigint;
  inserted_contacts bigint;
begin
  select count(*) into source_pets from public.pets;
  select count(*) into source_contacts from public.pet_contacts;

  if exists (select 1 from petlink.pets) then
    raise exception 'Migration stopped: petlink.pets is not empty. Review existing rows; do not overwrite them.';
  end if;
  if exists (select 1 from petlink.pet_contacts) then
    raise exception 'Migration stopped: petlink.pet_contacts is not empty. Review existing rows; do not overwrite them.';
  end if;
  if exists (
    select 1 from public.pets p
    left join petlink.app_users u on u.id = p.owner_id
    where u.id is null
  ) then
    raise exception 'Migration stopped: at least one pet owner is missing from petlink.app_users.';
  end if;
  if exists (select 1 from public.pets where public_id is null) then
    raise exception 'Migration stopped: at least one legacy public_id is null.';
  end if;
  if exists (
    select public_id from public.pets
    group by public_id having count(*) > 1
  ) then
    raise exception 'Migration stopped: duplicate legacy public_id values found.';
  end if;

  insert into petlink.pets (
    id, name, species, breed, public_description,
    public_contact_enabled, public_phone, public_email,
    important_information, lost_mode, lost_message,
    lost_mode_started_at, is_public, created_at, updated_at,
    legacy_public_id, sex, birth_date, color,
    medical_alerts, show_medical_alerts, legacy_species
  )
  select
    p.id, p.name,
    case
      when lower(btrim(p.species)) in ('dog', 'perro') then 'dog'
      when lower(btrim(p.species)) in ('cat', 'gato') then 'cat'
      else 'other'
    end,
    p.breed, p.public_description,
    exists (select 1 from public.pet_contacts c
            where c.pet_id = p.id and c.is_public = true),
    null, null, null,
    p.is_lost, null, null, p.is_public,
    p.created_at, p.updated_at, p.public_id, p.sex,
    p.birth_date, p.color, p.medical_alerts,
    p.show_medical_alerts, p.species
  from public.pets p;

  get diagnostics inserted_pets = row_count;

  insert into petlink.pet_members (
    pet_id, user_id, role, invited_by, accepted_at, created_at
  )
  select p.id, p.owner_id, 'owner'::petlink.membership_role,
         null, p.created_at, p.created_at
  from public.pets p;

  insert into petlink.pet_contacts (
    id, pet_id, name, relationship, phone, email,
    whatsapp_enabled, is_public, sort_order, created_at
  )
  select c.id, c.pet_id, c.name, c.relationship, c.phone, c.email,
         c.whatsapp_enabled, c.is_public, c.sort_order, c.created_at
  from public.pet_contacts c;

  get diagnostics inserted_contacts = row_count;

  if inserted_pets <> source_pets then
    raise exception 'Migration stopped: pet count mismatch (source %, inserted %).',
      source_pets, inserted_pets;
  end if;
  if inserted_contacts <> source_contacts then
    raise exception 'Migration stopped: contact count mismatch (source %, inserted %).',
      source_contacts, inserted_contacts;
  end if;
  if exists (
    select 1 from public.pets p
    left join petlink.pets n on n.id = p.id and n.legacy_public_id = p.public_id
    where n.id is null
  ) then
    raise exception 'Migration stopped: pet UUID or legacy public ID mismatch.';
  end if;
  if exists (
    select 1 from public.pets p
    left join petlink.pet_members m
      on m.pet_id = p.id and m.user_id = p.owner_id and m.role = 'owner'
    where m.pet_id is null
  ) then
    raise exception 'Migration stopped: owner membership validation failed.';
  end if;
  if exists (
    select 1 from public.pet_contacts c
    left join petlink.pet_contacts n
      on n.id = c.id and n.pet_id = c.pet_id and n.is_public = c.is_public
    where n.id is null
  ) then
    raise exception 'Migration stopped: contact identity or visibility validation failed.';
  end if;
end
$migration$;

select
  (select count(*) from public.pets) as source_pets,
  (select count(*) from petlink.pets) as migrated_pets,
  (select count(*) from public.pet_contacts) as source_contacts,
  (select count(*) from petlink.pet_contacts) as migrated_contacts,
  (select count(*) from petlink.pet_members where role = 'owner') as owner_memberships;

-- For a rehearsal, replace COMMIT with ROLLBACK before running.
commit;
