-- HUËLLIK promotions tables v1
-- DRAFT ONLY: review before applying to the existing Supabase project.
-- No direct access is granted to anon/authenticated; private schema stays private.

begin;

create table if not exists petlink.promo_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  description text null,
  discount_type text not null check (discount_type in ('percent','fixed')),
  discount_value numeric(10,2) not null check (discount_value > 0),
  currency char(3) not null default 'EUR' check (currency = 'EUR'),
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
  currency char(3) not null default 'EUR' check (currency = 'EUR'),
  reserved_at timestamptz not null default now(),
  redeemed_at timestamptz null,
  voided_at timestamptz null,
  created_at timestamptz not null default now()
);

create index if not exists promo_redemptions_code_status_idx
  on petlink.promo_redemptions (promo_code_id, status);
create index if not exists promo_redemptions_user_code_idx
  on petlink.promo_redemptions (user_id, promo_code_id, status);

alter table petlink.promo_codes enable row level security;
alter table petlink.promo_redemptions enable row level security;

revoke all on table petlink.promo_codes, petlink.promo_redemptions
  from public, anon, authenticated;

commit;
