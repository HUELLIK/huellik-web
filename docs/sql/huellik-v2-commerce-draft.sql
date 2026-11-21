-- HUËLLIK v2 commerce and access-control draft
-- NOT A PRODUCTION MIGRATION. Review and test in an isolated environment before applying.
-- Historical product schema: petlink. Do not rename or delete existing tables.
-- All operations are intended to be performed by trusted Edge Functions using service_role.
-- No direct anon/authenticated access is granted.

begin;

create table if not exists petlink.admin_users (
  user_id uuid primary key references petlink.app_users(id) on delete cascade,
  role text not null default 'owner' check (role = 'owner'),
  created_at timestamptz not null default now(),
  created_by uuid null references petlink.app_users(id) on delete set null
);

create table if not exists petlink.promo_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  description text null,
  discount_type text not null check (discount_type in ('percent','fixed')),
  discount_value numeric(10,2) not null check (discount_value > 0),
  currency char(3) not null default 'EUR',
  applies_to text[] not null default array['all']::text[],
  starts_at timestamptz not null default now(),
  expires_at timestamptz null,
  max_redemptions integer null check (max_redemptions is null or max_redemptions > 0),
  max_redemptions_per_user integer not null default 1 check (max_redemptions_per_user > 0),
  first_time_only boolean not null default false,
  active boolean not null default true,
  created_by uuid null references petlink.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint promo_code_format check (code = upper(trim(code)) and char_length(code) between 3 and 40),
  constraint promo_code_expiry check (expires_at is null or expires_at > starts_at),
  constraint promo_code_scope_nonempty check (cardinality(applies_to) > 0),
  constraint promo_code_percent_range check (discount_type <> 'percent' or discount_value <= 100)
);

create unique index if not exists promo_codes_code_uq on petlink.promo_codes (upper(code));
create index if not exists promo_codes_active_window_idx on petlink.promo_codes (active, starts_at, expires_at);

create table if not exists petlink.promo_redemptions (
  id uuid primary key default gen_random_uuid(),
  promo_code_id uuid not null references petlink.promo_codes(id) on delete restrict,
  user_id uuid not null references petlink.app_users(id) on delete restrict,
  order_id uuid null references petlink.orders(id) on delete set null,
  subscription_id uuid null references petlink.subscriptions(id) on delete set null,
  checkout_session_id text null unique,
  status text not null default 'reserved' check (status in ('reserved','redeemed','void')),
  discount_amount numeric(10,2) not null check (discount_amount >= 0),
  currency char(3) not null default 'EUR',
  reserved_at timestamptz not null default now(),
  redeemed_at timestamptz null,
  voided_at timestamptz null,
  created_at timestamptz not null default now()
);
create index if not exists promo_redemptions_code_status_idx on petlink.promo_redemptions (promo_code_id, status);
create index if not exists promo_redemptions_user_code_idx on petlink.promo_redemptions (user_id, promo_code_id, status);

create table if not exists petlink.entitlement_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references petlink.app_users(id) on delete cascade,
  pet_id uuid null references petlink.pets(id) on delete cascade,
  entitlement_code text not null,
  source_type text not null check (source_type in ('subscription','order','promotion','gift','admin')),
  source_reference text null,
  status text not null default 'active' check (status in ('active','revoked','expired')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz null,
  revoked_at timestamptz null,
  created_by uuid null references petlink.app_users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint entitlement_period_valid check (ends_at is null or ends_at > starts_at)
);
create index if not exists entitlement_grants_user_status_idx on petlink.entitlement_grants (user_id, entitlement_code, status, starts_at, ends_at);
create index if not exists entitlement_grants_pet_idx on petlink.entitlement_grants (pet_id) where pet_id is not null;
create unique index if not exists entitlement_source_unique_idx
  on petlink.entitlement_grants (user_id, entitlement_code, source_type, source_reference)
  where source_reference is not null;

create table if not exists petlink.webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('stripe')),
  event_id text not null,
  event_type text not null,
  provider_object_id text null,
  status text not null default 'received' check (status in ('received','processing','processed','failed')),
  received_at timestamptz not null default now(),
  processed_at timestamptz null,
  last_error text null,
  unique (provider, event_id)
);
create index if not exists webhook_events_status_received_idx on petlink.webhook_events (status, received_at);

-- New tables are private. RLS is defense in depth; only trusted server functions use service_role.
alter table petlink.admin_users enable row level security;
alter table petlink.promo_codes enable row level security;
alter table petlink.promo_redemptions enable row level security;
alter table petlink.entitlement_grants enable row level security;
alter table petlink.webhook_events enable row level security;

revoke all on table petlink.admin_users, petlink.promo_codes, petlink.promo_redemptions,
  petlink.entitlement_grants, petlink.webhook_events from public, anon, authenticated;
grant usage on schema petlink to service_role;
grant select, insert, update, delete on table petlink.admin_users, petlink.promo_codes,
  petlink.promo_redemptions, petlink.entitlement_grants, petlink.webhook_events to service_role;

commit;

-- API SCHEMA NOTE:
-- The audited project currently has no USAGE grant on schema petlink for service_role,
-- anon or authenticated. This draft grants USAGE only to service_role. If Edge Functions
-- use the Supabase Data API/PostgREST to access petlink tables directly, the petlink schema
-- must also be added to the project's exposed Data API schemas. Exposing a schema does not
-- itself grant table access: keep all table grants revoked from anon/authenticated and grant
-- only service_role. If you do not want petlink exposed through PostgREST at all, implement
-- narrowly scoped public RPC wrappers with EXECUTE granted only to service_role instead.
-- Verify the actual Data API schema configuration before selecting either approach.

-- IMPORTANT IMPLEMENTATION NOTES:
-- 1. Do not seed admin_users until the owner account UUID has been confirmed.
-- 2. Edge Functions must validate the caller's JWT with Supabase Auth, then check admin_users
--    server-side for admin actions. Never trust user_metadata or a browser-supplied role.
-- 3. Promo validation and redemption reservation must be transactional: lock the promo row
--    (SELECT ... FOR UPDATE), check dates/scope/global and per-user limits, then reserve.
-- 4. On successful Stripe payment, mark the reservation redeemed and insert the entitlement
--    in the same database transaction. On expiry/cancellation, void the reservation.
-- 5. Verify Stripe webhook signatures, store each event id once, and make processing idempotent.
-- 6. Stripe secret keys and Supabase service_role stay in server-side secrets only.
-- 7. Validate percent discounts against the eligible subtotal; fixed discounts cannot exceed it.
-- 8. Do not activate recurring billing or renewals without an explicit customer opt-in.
