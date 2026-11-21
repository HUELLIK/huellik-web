-- HUËLLIK audited QR/NFC identifier lifecycle v1
create or replace function public.huellik_admin_identifier_action_v1(
  p_action text,
  p_identifier_id uuid,
  p_replacement_identifier_id uuid default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_reason text := trim(coalesce(p_reason,''));
  v_old petlink.identifiers%rowtype;
  v_new petlink.identifiers%rowtype;
  v_target_status petlink.identifier_status;
  v_event_type text;
begin
  if v_user_id is null then
    raise insufficient_privilege using message='Authentication required';
  end if;
  if not exists(select 1 from petlink.admin_users a where a.user_id=v_user_id and a.role='owner') then
    raise insufficient_privilege using message='Administrator access required';
  end if;
  if p_action not in ('activate','mark_lost','mark_found','disable','replace') then
    raise invalid_parameter_value using message='Unsupported identifier action';
  end if;
  if char_length(v_reason)<8 or char_length(v_reason)>300 then
    raise invalid_parameter_value using message='A reason between 8 and 300 characters is required';
  end if;
  if p_identifier_id is null then
    raise invalid_parameter_value using message='Identifier is required';
  end if;

  select * into v_old from petlink.identifiers where id=p_identifier_id for update;
  if not found then raise no_data_found using message='Identifier not found'; end if;

  if p_action='replace' then
    if p_replacement_identifier_id is null or p_replacement_identifier_id=p_identifier_id then
      raise invalid_parameter_value using message='A different replacement identifier is required';
    end if;
    select * into v_new from petlink.identifiers where id=p_replacement_identifier_id for update;
    if not found then raise no_data_found using message='Replacement identifier not found'; end if;
    if v_old.pet_id<>v_new.pet_id then
      raise check_violation using message='Replacement must belong to the same pet';
    end if;
    if v_old.status not in ('active','lost') or v_new.status<>'pending' then
      raise check_violation using message='Only an active or lost identifier can be replaced by a pending identifier';
    end if;
    update petlink.identifiers set status='replaced' where id=v_old.id;
    update petlink.identifiers set status='active', activated_at=coalesce(activated_at,now()) where id=v_new.id;
    v_event_type:='identifier_replaced';
    insert into petlink.audit_events(actor_user_id,pet_id,event_type,event_data)
    values(v_user_id,v_old.pet_id,v_event_type,jsonb_build_object(
      'old_identifier_id',v_old.id,'new_identifier_id',v_new.id,
      'old_status',v_old.status::text,'new_status_before','pending','new_status_after','active',
      'reason',v_reason
    ));
    return jsonb_build_object('action',p_action,'old_identifier_id',v_old.id,
      'new_identifier_id',v_new.id,'old_status','replaced','new_status','active');
  end if;

  if p_action='activate' then
    if v_old.status<>'pending' then raise check_violation using message='Only pending identifiers can be activated'; end if;
    v_target_status:='active'; v_event_type:='identifier_activated';
    update petlink.identifiers set status=v_target_status,activated_at=coalesce(activated_at,now()) where id=v_old.id;
  elsif p_action='mark_lost' then
    if v_old.status<>'active' then raise check_violation using message='Only active identifiers can be marked lost'; end if;
    v_target_status:='lost'; v_event_type:='identifier_marked_lost';
    update petlink.identifiers set status=v_target_status where id=v_old.id;
  elsif p_action='mark_found' then
    if v_old.status<>'lost' then raise check_violation using message='Only lost identifiers can be marked found'; end if;
    v_target_status:='active'; v_event_type:='identifier_marked_found';
    update petlink.identifiers set status=v_target_status where id=v_old.id;
  else
    if v_old.status not in ('pending','active','lost') then raise check_violation using message='This identifier cannot be disabled from its current status'; end if;
    v_target_status:='disabled'; v_event_type:='identifier_disabled';
    update petlink.identifiers set status=v_target_status where id=v_old.id;
  end if;

  insert into petlink.audit_events(actor_user_id,pet_id,event_type,event_data)
  values(v_user_id,v_old.pet_id,v_event_type,jsonb_build_object(
    'identifier_id',v_old.id,'identifier_kind',v_old.identifier_kind::text,
    'from_status',v_old.status::text,'to_status',v_target_status::text,'reason',v_reason
  ));
  return jsonb_build_object('action',p_action,'identifier_id',v_old.id,
    'previous_status',v_old.status::text,'status',v_target_status::text);
end;
$function$;

create or replace function public.huellik_admin_identifier_audit_v1(
  p_identifier_id uuid default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_rows jsonb;
  v_total bigint;
  v_limit integer := greatest(1,least(coalesce(p_limit,50),100));
  v_offset integer := greatest(0,least(coalesce(p_offset,0),100000));
begin
  if v_user_id is null then raise insufficient_privilege using message='Authentication required'; end if;
  if not exists(select 1 from petlink.admin_users a where a.user_id=v_user_id and a.role='owner') then
    raise insufficient_privilege using message='Administrator access required';
  end if;
  select count(*) into v_total
  from petlink.audit_events e
  where e.event_type in ('identifier_activated','identifier_marked_lost','identifier_marked_found','identifier_disabled','identifier_replaced')
    and (p_identifier_id is null or e.event_data->>'identifier_id'=p_identifier_id::text
      or e.event_data->>'old_identifier_id'=p_identifier_id::text
      or e.event_data->>'new_identifier_id'=p_identifier_id::text);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_rows
  from (
    select e.id,e.pet_id,e.event_type,e.event_data,e.created_at,
      coalesce(u.display_name,'Administrador') as actor_name
    from petlink.audit_events e
    left join petlink.app_users u on u.id=e.actor_user_id
    where e.event_type in ('identifier_activated','identifier_marked_lost','identifier_marked_found','identifier_disabled','identifier_replaced')
      and (p_identifier_id is null or e.event_data->>'identifier_id'=p_identifier_id::text
        or e.event_data->>'old_identifier_id'=p_identifier_id::text
        or e.event_data->>'new_identifier_id'=p_identifier_id::text)
    order by e.created_at desc,e.id desc
    limit v_limit offset v_offset
  ) x;
  return jsonb_build_object('events',v_rows,'total',v_total,'limit',v_limit,'offset',v_offset);
end;
$function$;

revoke all on function public.huellik_admin_identifier_action_v1(text,uuid,uuid,text) from public;
revoke all on function public.huellik_admin_identifier_action_v1(text,uuid,uuid,text) from anon;
grant execute on function public.huellik_admin_identifier_action_v1(text,uuid,uuid,text) to authenticated;
revoke all on function public.huellik_admin_identifier_audit_v1(uuid,integer,integer) from public;
revoke all on function public.huellik_admin_identifier_audit_v1(uuid,integer,integer) from anon;
grant execute on function public.huellik_admin_identifier_audit_v1(uuid,integer,integer) to authenticated;
