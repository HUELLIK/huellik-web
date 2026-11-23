-- HUËLLIK: physical tag inventory and activation
-- Additive migration. Existing public.pets and legacy identifiers remain untouched.

create table if not exists petlink.tag_links (
  id uuid primary key default gen_random_uuid(),
  public_code text not null unique,
  destination_url text not null unique,
  nfc_uid text unique,
  supplier_reference text,
  activation_secret_hash text not null,
  public_pet_id uuid references public.pets(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','active','lost','disabled','replaced')),
  activated_by uuid references auth.users(id) on delete set null,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tag_links_public_code_check check (public_code ~ '^[A-Za-z0-9_-]{6,64}$'),
  constraint tag_links_secret_hash_check check (activation_secret_hash ~ '^[0-9a-f]{64}$'),
  constraint tag_links_active_binding_check check (
    (status in ('active','lost') and public_pet_id is not null)
    or status not in ('active','lost')
  )
);

create index if not exists tag_links_public_pet_id_idx
  on petlink.tag_links(public_pet_id) where public_pet_id is not null;

alter table petlink.tag_links enable row level security;
revoke all on table petlink.tag_links from anon, authenticated, public;

-- Return only the state needed to decide whether to show the activation screen.
create or replace function public.huellik_tag_status_v1(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status text;
begin
  if p_code is null or length(trim(p_code)) < 6 or length(trim(p_code)) > 64 then
    return jsonb_build_object('state','unavailable');
  end if;

  select t.status into v_status
  from petlink.tag_links t
  where t.public_code = trim(p_code);

  if not found then
    return jsonb_build_object('state','unavailable');
  end if;

  if v_status = 'pending' then
    return jsonb_build_object('state','pending');
  elsif v_status in ('active','lost') then
    return jsonb_build_object('state',v_status);
  end if;

  return jsonb_build_object('state','unavailable');
end;
$function$;

revoke all on function public.huellik_tag_status_v1(text) from public;
grant execute on function public.huellik_tag_status_v1(text) to anon, authenticated;

-- Activation is only possible for a signed-in owner of an existing public.pets row.
create or replace function public.huellik_activate_tag_v1(
  p_code text,
  p_activation_secret text,
  p_pet_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_tag petlink.tag_links%rowtype;
begin
  if v_user_id is null then
    raise insufficient_privilege using message = 'Inicia sesión para activar la chapa.';
  end if;

  if p_code is null or p_activation_secret is null or p_pet_id is null then
    raise invalid_parameter_value using message = 'Faltan datos para activar la chapa.';
  end if;

  select * into v_tag
  from petlink.tag_links
  where public_code = trim(p_code)
  for update;

  if not found then
    raise no_data_found using message = 'La chapa no está disponible.';
  end if;

  if v_tag.status <> 'pending' then
    raise check_violation using message = 'Esta chapa ya está activada o no se puede activar.';
  end if;

  if v_tag.activation_secret_hash <>
     encode(extensions.digest(convert_to(upper(trim(p_activation_secret)), 'UTF8'), 'sha256'), 'hex') then
    raise insufficient_privilege using message = 'El código de activación no es correcto.';
  end if;

  if not exists (
    select 1 from public.pets p
    where p.id = p_pet_id and p.owner_id = v_user_id
  ) then
    raise insufficient_privilege using message = 'No puedes vincular esta chapa a esa mascota.';
  end if;

  update petlink.tag_links
  set public_pet_id = p_pet_id,
      status = 'active',
      activated_by = v_user_id,
      activated_at = now(),
      updated_at = now()
  where id = v_tag.id;

  insert into petlink.audit_events(actor_user_id, pet_id, event_type, event_data)
  values (
    v_user_id,
    p_pet_id,
    'tag_activated',
    jsonb_build_object(
      'tag_id', v_tag.id,
      'public_code', v_tag.public_code,
      'nfc_uid', v_tag.nfc_uid,
      'supplier_reference', v_tag.supplier_reference
    )
  );

  return jsonb_build_object('success', true, 'state', 'active');
end;
$function$;

revoke all on function public.huellik_activate_tag_v1(text,text,uuid) from public, anon;
grant execute on function public.huellik_activate_tag_v1(text,text,uuid) to authenticated;

-- Resolve physical tag codes first; preserve the existing legacy resolver for old pet QR links.
alter function public.resolve_public_pet_profile(text)
  rename to resolve_public_pet_profile_legacy;

create or replace function public.resolve_public_pet_profile(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tag petlink.tag_links%rowtype;
begin
  if p_code is null or length(trim(p_code)) = 0 or length(trim(p_code)) > 200 then
    return jsonb_build_object('error','not_found');
  end if;

  select * into v_tag
  from petlink.tag_links t
  where t.public_code = trim(p_code);

  if found then
    if v_tag.status not in ('active','lost') or v_tag.public_pet_id is null then
      return jsonb_build_object('error','not_found');
    end if;
    return public.get_public_pet_profile(v_tag.public_pet_id);
  end if;

  return public.resolve_public_pet_profile_legacy(p_code);
end;
$function$;

revoke all on function public.resolve_public_pet_profile(text) from public;
grant execute on function public.resolve_public_pet_profile(text) to anon, authenticated;
