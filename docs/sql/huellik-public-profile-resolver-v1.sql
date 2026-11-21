-- HUËLLIK v2 — public profile resolver v1
-- Applied to Supabase project tgdxjfjbldlqsoeinuwm.
-- Public execution is intentional: this RPC returns only the curated public profile.

create or replace function public.resolve_public_pet_profile(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_code text := nullif(btrim(p_code), '');
  v_pet petlink.pets%rowtype;
  v_uuid uuid;
  v_contacts jsonb := '[]'::jsonb;
  v_color text := null;
  v_medical_alerts text := null;
  v_show_medical boolean := false;
  v_legacy_row_exists boolean := false;
begin
  if v_code is null or char_length(v_code) > 200 then
    return jsonb_build_object('error','not_found');
  end if;

  select p.* into v_pet
  from petlink.identifiers i
  join petlink.pets p on p.id = i.pet_id
  where i.public_code = v_code
    and i.status = 'active'::petlink.identifier_status
    and p.is_public = true
  order by i.created_at desc
  limit 1;

  if v_pet.id is null then
    begin
      v_uuid := v_code::uuid;
    exception when invalid_text_representation then
      v_uuid := null;
    end;

    if v_uuid is not null and exists (
      select 1 from information_schema.columns c
      where c.table_schema='petlink'
        and c.table_name='pets'
        and c.column_name='legacy_public_id'
    ) then
      execute
        'select p.* from petlink.pets p where p.legacy_public_id = $1 and p.is_public = true limit 1'
        into v_pet using v_uuid;

      execute
        'select exists(select 1 from petlink.pets p where p.legacy_public_id = $1)'
        into v_legacy_row_exists using v_uuid;
    end if;
  end if;

  if v_pet.id is not null then
    if to_regclass('petlink.pet_contacts') is not null then
      execute $sql$
        select coalesce(
          jsonb_agg(jsonb_build_object(
            'name', c.name,
            'relationship', c.relationship,
            'phone', c.phone,
            'email', c.email,
            'whatsapp_enabled', c.whatsapp_enabled
          ) order by c.sort_order, c.created_at),
          '[]'::jsonb
        )
        from petlink.pet_contacts c
        where c.pet_id = $1 and c.is_public = true
      $sql$ into v_contacts using v_pet.id;
    end if;

    if exists (
      select 1 from information_schema.columns c
      where c.table_schema='petlink' and c.table_name='pets'
        and c.column_name='color'
    ) then
      execute 'select color from petlink.pets where id=$1'
        into v_color using v_pet.id;
    end if;

    if exists (
      select 1 from information_schema.columns c
      where c.table_schema='petlink' and c.table_name='pets'
        and c.column_name='medical_alerts'
    ) then
      execute
        'select coalesce(show_medical_alerts,false), case when show_medical_alerts then medical_alerts else null end from petlink.pets where id=$1'
        into v_show_medical, v_medical_alerts using v_pet.id;
    end if;

    return jsonb_build_object(
      'name', v_pet.name,
      'species', v_pet.species,
      'breed', v_pet.breed,
      'color', v_color,
      'public_description', v_pet.public_description,
      'is_lost', v_pet.lost_mode,
      'show_medical_alerts', v_show_medical,
      'medical_alerts', v_medical_alerts,
      'contacts', v_contacts
    );
  end if;

  if v_legacy_row_exists then
    return jsonb_build_object('error','not_found');
  end if;

  begin
    v_uuid := v_code::uuid;
  exception when invalid_text_representation then
    v_uuid := null;
  end;

  if v_uuid is not null then
    return public.get_public_pet_profile(v_uuid);
  end if;

  return jsonb_build_object('error','not_found');
end;
$function$;

revoke all on function public.resolve_public_pet_profile(text) from public;
revoke all on function public.resolve_public_pet_profile(text) from anon, authenticated;
grant execute on function public.resolve_public_pet_profile(text) to anon, authenticated;
