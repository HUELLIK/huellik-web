-- HUËLLIK admin pets + QR/NFC v1
-- Read-only. Current customer pets remain in public.pets.
-- petlink identifiers are shown separately until the planned data migration is validated.
create or replace function public.huellik_admin_pets_v1(
  p_query text default '',
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_query text := lower(trim(coalesce(p_query, '')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  v_offset integer := greatest(0, least(coalesce(p_offset, 0), 100000));
  v_pet_total bigint := 0;
  v_pet_rows jsonb := '[]'::jsonb;
  v_identifier_total bigint := 0;
  v_identifier_rows jsonb := '[]'::jsonb;
  v_metrics jsonb;
begin
  if v_user_id is null then
    raise insufficient_privilege using message = 'Authentication required';
  end if;
  if not exists (select 1 from petlink.admin_users a where a.user_id = v_user_id and a.role = 'owner') then
    raise insufficient_privilege using message = 'Administrator access required';
  end if;
  if char_length(v_query) > 80 then
    raise invalid_parameter_value using message = 'Search query too long';
  end if;

  select count(*) into v_pet_total
  from public.pets p left join public.profiles pr on pr.id = p.owner_id
  where v_query = ''
     or strpos(lower(p.name), v_query) > 0
     or strpos(lower(p.species), v_query) > 0
     or strpos(lower(coalesce(p.breed, '')), v_query) > 0
     or strpos(lower(p.public_id::text), v_query) > 0
     or strpos(lower(coalesce(pr.display_name, '')), v_query) > 0;

  select coalesce(jsonb_agg(to_jsonb(page_row) order by page_row.created_at desc), '[]'::jsonb)
  into v_pet_rows
  from (
    select p.id, p.public_id, p.name, p.species, p.breed, p.sex, p.birth_date, p.color,
           p.is_public, p.is_lost, p.created_at, p.updated_at,
           coalesce(pr.display_name, 'Sin nombre') as owner_name,
           (select count(*)::integer from public.pet_contacts c where c.pet_id = p.id) as contacts_count,
           (select count(*)::integer from petlink.identifiers i where i.pet_id = p.id) as identifier_count
    from public.pets p left join public.profiles pr on pr.id = p.owner_id
    where v_query = ''
       or strpos(lower(p.name), v_query) > 0
       or strpos(lower(p.species), v_query) > 0
       or strpos(lower(coalesce(p.breed, '')), v_query) > 0
       or strpos(lower(p.public_id::text), v_query) > 0
       or strpos(lower(coalesce(pr.display_name, '')), v_query) > 0
    order by p.created_at desc, p.id
    limit v_limit offset v_offset
  ) page_row;

  select count(*) into v_identifier_total from petlink.identifiers;
  select coalesce(jsonb_agg(to_jsonb(identifier_row) order by identifier_row.created_at desc), '[]'::jsonb)
  into v_identifier_rows
  from (
    select i.id, i.pet_id, i.identifier_kind::text as identifier_kind, i.public_code,
           i.status::text as status, i.created_at, i.activated_at,
           p.name as pet_name, p.species as pet_species,
           (select count(*)::integer from petlink.scans s where s.identifier_id = i.id) as scan_count,
           (select max(s.scanned_at) from petlink.scans s where s.identifier_id = i.id) as last_scanned_at
    from petlink.identifiers i join petlink.pets p on p.id = i.pet_id
    order by i.created_at desc, i.id
    limit 50
  ) identifier_row;

  select jsonb_build_object(
    'pets_total', (select count(*)::integer from public.pets),
    'pets_public', (select count(*)::integer from public.pets where is_public),
    'pets_lost', (select count(*)::integer from public.pets where is_lost),
    'pets_with_legacy_link', (select count(*)::integer from public.pets where public_id is not null),
    'identifiers_total', (select count(*)::integer from petlink.identifiers),
    'identifiers_active', (select count(*)::integer from petlink.identifiers where status = 'active'),
    'identifiers_pending', (select count(*)::integer from petlink.identifiers where status = 'pending'),
    'identifiers_lost', (select count(*)::integer from petlink.identifiers where status = 'lost'),
    'identifiers_replaced', (select count(*)::integer from petlink.identifiers where status = 'replaced'),
    'scans_total', (select count(*)::integer from petlink.scans)
  ) into v_metrics;

  return jsonb_build_object(
    'pets', v_pet_rows, 'pets_total', v_pet_total, 'pets_limit', v_limit, 'pets_offset', v_offset,
    'identifiers', v_identifier_rows, 'identifiers_total', v_identifier_total, 'identifiers_limit', 50,
    'metrics', v_metrics,
    'data_sources', jsonb_build_object('pets', 'public.pets', 'identifiers', 'petlink.identifiers',
      'identifiers_linked_to_current_pets', false)
  );
end;
$function$;
revoke all on function public.huellik_admin_pets_v1(text,integer,integer) from public;
revoke all on function public.huellik_admin_pets_v1(text,integer,integer) from anon;
grant execute on function public.huellik_admin_pets_v1(text,integer,integer) to authenticated;
