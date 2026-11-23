alter table petlink.tag_links
  add column if not exists failed_activation_attempts integer not null default 0,
  add column if not exists activation_locked_until timestamptz;
create or replace function public.huellik_activate_tag_v1(p_code text,p_activation_secret text,p_pet_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare v_user_id uuid:=auth.uid(); v_actor_id uuid; v_tag petlink.tag_links%rowtype;
begin
 if v_user_id is null then raise insufficient_privilege using message='Inicia sesión para activar la chapa.'; end if;
 if p_code is null or p_activation_secret is null or p_pet_id is null then raise invalid_parameter_value using message='Faltan datos para activar la chapa.'; end if;
 select * into v_tag from petlink.tag_links where public_code=trim(p_code) for update;
 if not found then return jsonb_build_object('success',false,'message','La chapa no está disponible.'); end if;
 if v_tag.status<>'pending' then return jsonb_build_object('success',false,'message','Esta chapa ya está activada o no se puede activar.'); end if;
 if v_tag.activation_locked_until is not null and v_tag.activation_locked_until>now() then return jsonb_build_object('success',false,'message','Se han realizado demasiados intentos. Prueba de nuevo dentro de 15 minutos.'); end if;
 if v_tag.activation_secret_hash<>encode(extensions.digest(convert_to(upper(trim(p_activation_secret)),'UTF8'),'sha256'),'hex') then
  update petlink.tag_links set failed_activation_attempts=failed_activation_attempts+1,
   activation_locked_until=case when failed_activation_attempts+1>=5 then now()+interval '15 minutes' else null end,
   updated_at=now() where id=v_tag.id;
  if v_tag.failed_activation_attempts+1>=5 then return jsonb_build_object('success',false,'message','Has alcanzado el máximo de intentos. La activación queda bloqueada durante 15 minutos.'); end if;
  return jsonb_build_object('success',false,'message','El código secreto no es correcto. Te quedan '||(4-v_tag.failed_activation_attempts)::text||' intentos antes del bloqueo.');
 end if;
 if not exists(select 1 from public.pets p where p.id=p_pet_id and p.owner_id=v_user_id) then return jsonb_build_object('success',false,'message','No puedes vincular esta chapa a esa mascota.'); end if;
 update petlink.tag_links set public_pet_id=p_pet_id,status='active',activated_by=v_user_id,activated_at=now(),failed_activation_attempts=0,activation_locked_until=null,updated_at=now() where id=v_tag.id;
 select id into v_actor_id from petlink.app_users where id=v_user_id;
 insert into petlink.audit_events(actor_user_id,event_type,event_data) values(v_actor_id,'tag_activated',jsonb_build_object('tag_id',v_tag.id,'public_code',v_tag.public_code,'public_pet_id',p_pet_id,'nfc_uid',v_tag.nfc_uid,'supplier_reference',v_tag.supplier_reference));
 return jsonb_build_object('success',true,'state','active');
end;
$function$;
revoke all on function public.huellik_activate_tag_v1(text,text,uuid) from public,anon;
grant execute on function public.huellik_activate_tag_v1(text,text,uuid) to authenticated;