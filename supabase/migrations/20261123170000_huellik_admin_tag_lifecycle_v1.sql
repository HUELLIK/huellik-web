-- HUËLLIK tag lifecycle management: admin-only listing, lost/found, disable and replacement.
alter table petlink.tag_links
  add column if not exists replacement_tag_id uuid references petlink.tag_links(id) on delete set null,
  add column if not exists replaced_at timestamptz,
  add column if not exists disabled_at timestamptz;

create or replace function public.huellik_admin_tag_lifecycle_v1(
  p_action text,
  p_tag_id uuid default null,
  p_replacement_tag_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_actor_id uuid;
  v_tag petlink.tag_links%rowtype;
  v_new_tag petlink.tag_links%rowtype;
  v_tags jsonb;
begin
  if v_user_id is null then
    raise insufficient_privilege using message = 'Authentication required';
  end if;
  if not exists (
    select 1 from petlink.admin_users a
    where a.user_id = v_user_id and a.role = 'owner'
  ) then
    raise insufficient_privilege using message = 'Administrator access required';
  end if;
  select id into v_actor_id from petlink.app_users where id = v_user_id;

  if p_action = 'list' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'public_code', t.public_code, 'nfc_uid', t.nfc_uid,
      'supplier_reference', t.supplier_reference, 'status', t.status,
      'pet_id', t.public_pet_id, 'pet_name', p.name,
      'created_at', t.created_at, 'activated_at', t.activated_at,
      'replaced_at', t.replaced_at, 'disabled_at', t.disabled_at,
      'replacement_tag_id', t.replacement_tag_id
    ) order by t.created_at desc), '[]'::jsonb)
    into v_tags
    from petlink.tag_links t
    left join public.pets p on p.id = t.public_pet_id;
    return jsonb_build_object('tags', v_tags);
  end if;

  if p_tag_id is null then
    raise invalid_parameter_value using message = 'Selecciona una chapa.';
  end if;
  select * into v_tag from petlink.tag_links where id = p_tag_id for update;
  if not found then raise no_data_found using message = 'No se encuentra la chapa.'; end if;

  if p_action = 'mark_lost' then
    if v_tag.status not in ('active','lost') then raise check_violation using message = 'Solo puedes marcar como perdida una chapa activada.'; end if;
    update petlink.tag_links set status='lost', updated_at=now() where id=v_tag.id;
    update public.pets set is_lost=true, updated_at=now() where id=v_tag.public_pet_id;
  elsif p_action = 'mark_found' then
    if v_tag.status <> 'lost' then raise check_violation using message = 'La chapa no figura como perdida.'; end if;
    update petlink.tag_links set status='active', updated_at=now() where id=v_tag.id;
    update public.pets set is_lost=false, updated_at=now() where id=v_tag.public_pet_id;
  elsif p_action = 'disable' then
    if v_tag.status not in ('pending','active','lost') then raise check_violation using message = 'Esta chapa ya está deshabilitada o sustituida.'; end if;
    update petlink.tag_links set status='disabled', disabled_at=now(), updated_at=now() where id=v_tag.id;
    if v_tag.public_pet_id is not null and v_tag.status='lost' then
      update public.pets set is_lost=false, updated_at=now() where id=v_tag.public_pet_id;
    end if;
  elsif p_action = 'replace' then
    if v_tag.status not in ('active','lost') then raise check_violation using message = 'Solo puedes sustituir una chapa activada.'; end if;
    if p_replacement_tag_id is null or p_replacement_tag_id = v_tag.id then raise invalid_parameter_value using message = 'Selecciona otra chapa pendiente para sustituirla.'; end if;
    select * into v_new_tag from petlink.tag_links where id=p_replacement_tag_id for update;
    if not found or v_new_tag.status <> 'pending' then raise check_violation using message = 'La nueva chapa debe estar pendiente de activación.'; end if;
    update petlink.tag_links set status='replaced', replacement_tag_id=v_new_tag.id, replaced_at=now(), updated_at=now() where id=v_tag.id;
    update petlink.tag_links set status='active', public_pet_id=v_tag.public_pet_id, activated_by=v_user_id, activated_at=now(), updated_at=now() where id=v_new_tag.id;
    if v_tag.status='lost' then update public.pets set is_lost=false, updated_at=now() where id=v_tag.public_pet_id; end if;
  else
    raise invalid_parameter_value using message = 'Acción de ciclo de vida no válida.';
  end if;

  insert into petlink.audit_events(actor_user_id,event_type,event_data)
  values (
    v_actor_id,
    case p_action when 'mark_lost' then 'tag_marked_lost' when 'mark_found' then 'tag_marked_found' when 'disable' then 'tag_disabled' when 'replace' then 'tag_replaced' end,
    jsonb_build_object('tag_id',v_tag.id,'public_code',v_tag.public_code,
      'replacement_tag_id',case when p_action='replace' then v_new_tag.id else null end,
      'replacement_public_code',case when p_action='replace' then v_new_tag.public_code else null end,
      'public_pet_id',v_tag.public_pet_id)
  );
  return jsonb_build_object('success',true,'action',p_action);
end;
$function$;

revoke all on function public.huellik_admin_tag_lifecycle_v1(text,uuid,uuid) from public, anon;
grant execute on function public.huellik_admin_tag_lifecycle_v1(text,uuid,uuid) to authenticated;