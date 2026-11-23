create or replace function public.huellik_admin_tag_inventory_v1(p_action text,p_rows jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare v_user_id uuid:=auth.uid(); v_actor_id uuid; v_row jsonb; v_code text; v_url text; v_uid text; v_supplier text; v_secret text; v_tags jsonb:='[]'::jsonb; v_count integer:=0;
begin
 if v_user_id is null then raise insufficient_privilege using message='Authentication required'; end if;
 if not exists(select 1 from petlink.admin_users a where a.user_id=v_user_id and a.role='owner') then raise insufficient_privilege using message='Administrator access required'; end if;
 select id into v_actor_id from petlink.app_users where id=v_user_id;
 if p_action='check' then return jsonb_build_object('is_admin',true);
 elsif p_action='import' then
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>500 then raise invalid_parameter_value using message='El archivo debe contener entre 1 y 500 chapas.'; end if;
  for v_row in select value from jsonb_array_elements(p_rows) loop
   v_code:=trim(coalesce(v_row->>'public_code','')); v_url:=trim(coalesce(v_row->>'destination_url','')); v_uid:=nullif(trim(coalesce(v_row->>'nfc_uid','')),''); v_supplier:=nullif(trim(coalesce(v_row->>'supplier_reference','')),'');
   if v_code !~ '^[A-Za-z0-9_-]{6,64}$' then raise invalid_parameter_value using message='Hay un código QR vacío o con formato no válido.'; end if;
   if v_url !~ '^https://' or position('code='||v_code in v_url)=0 then raise invalid_parameter_value using message='Cada URL debe ser HTTPS e incluir el código de su QR.'; end if;
   if v_uid is not null and length(v_uid)>128 then raise invalid_parameter_value using message='Hay un UID NFC demasiado largo.'; end if;
   v_secret:=upper(encode(extensions.gen_random_bytes(10),'hex'));
   insert into petlink.tag_links(public_code,destination_url,nfc_uid,supplier_reference,activation_secret_hash) values(v_code,v_url,v_uid,v_supplier,encode(extensions.digest(convert_to(v_secret,'UTF8'),'sha256'),'hex'));
   insert into petlink.audit_events(actor_user_id,event_type,event_data) values(v_actor_id,'tag_imported',jsonb_build_object('public_code',v_code,'nfc_uid',v_uid,'supplier_reference',v_supplier));
   v_tags:=v_tags||jsonb_build_array(jsonb_build_object('public_code',v_code,'activation_secret',v_secret)); v_count:=v_count+1;
  end loop;
  return jsonb_build_object('success',true,'imported',v_count,'tags',v_tags);
 elsif p_action='summary' then
  select jsonb_build_object('total',count(*),'pending',count(*) filter(where status='pending'),'active',count(*) filter(where status='active'),'disabled',count(*) filter(where status in ('disabled','replaced'))) into v_tags from petlink.tag_links;
  return v_tags;
 else raise invalid_parameter_value using message='Unsupported inventory action';
 end if;
end;
$function$;
revoke all on function public.huellik_admin_tag_inventory_v1(text,jsonb) from public,anon;
grant execute on function public.huellik_admin_tag_inventory_v1(text,jsonb) to authenticated;