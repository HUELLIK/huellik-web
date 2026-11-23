-- Let family admins manage invitations and members; audit removals.
create or replace function public.huellik_family_v1(p_action text,p_pet_id uuid default null,p_email text default null,p_role text default 'viewer',p_token text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_pet public.pets%rowtype; v_token text; v_email text; v_role petlink.membership_role; v_member jsonb; v_my_role text;
begin
 if v_uid is null then raise insufficient_privilege using message='Inicia sesión.'; end if;
 if p_action='accept' then
  if p_token is null or length(p_token)<20 then raise invalid_parameter_value using message='Código de invitación no válido.'; end if;
  select p.* into v_pet from public.pets p join petlink.pet_family_invites i on i.pet_id=p.id where i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and i.accepted_at is null and i.revoked_at is null and i.expires_at>now() and lower(i.email)=(select lower(email) from auth.users where id=v_uid) limit 1;
  if not found then raise insufficient_privilege using message='Invitación caducada, revocada o destinada a otro correo.'; end if;
  insert into petlink.pet_family_members(pet_id,user_id,role,invited_by) select i.pet_id,v_uid,i.role,i.invited_by from petlink.pet_family_invites i where i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') on conflict(pet_id,user_id) do update set role=excluded.role;
  update petlink.pet_family_invites set accepted_at=now() where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
  return jsonb_build_object('success',true,'message','Invitación aceptada.');
 end if;
 if p_action='list' then
  if p_pet_id is null then return jsonb_build_object('pets',coalesce((select jsonb_agg(jsonb_build_object('pet_id',p.id,'pet_name',p.name,'role','owner')) from public.pets p where p.owner_id=v_uid),'[]'::jsonb)||coalesce((select jsonb_agg(jsonb_build_object('pet_id',p.id,'pet_name',p.name,'role',m.role::text)) from petlink.pet_family_members m join public.pets p on p.id=m.pet_id where m.user_id=v_uid),'[]'::jsonb)); end if;
  if not public.huellik_family_can_access_pet(p_pet_id) then raise insufficient_privilege using message='No tienes acceso a esta mascota.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('email',u.email,'role',m.role::text,'user_id',m.user_id)),'[]'::jsonb) into v_member from petlink.pet_family_members m join auth.users u on u.id=m.user_id where m.pet_id=p_pet_id;
  select case when p.owner_id=v_uid then 'owner' else m.role::text end into v_my_role from public.pets p left join petlink.pet_family_members m on m.pet_id=p.id and m.user_id=v_uid where p.id=p_pet_id;
  return jsonb_build_object('members',v_member,'is_owner',v_my_role='owner','my_role',v_my_role,'can_manage',v_my_role in('owner','admin'));
 end if;
 if p_action in('invite','revoke','remove') then
  if p_pet_id is null or not exists(select 1 from public.pets p where p.id=p_pet_id and (p.owner_id=v_uid or exists(select 1 from petlink.pet_family_members m where m.pet_id=p.id and m.user_id=v_uid and m.role='admin'))) then raise insufficient_privilege using message='No tienes permisos para gestionar la familia de esta mascota.'; end if;
  if p_action='invite' then
   v_email:=lower(trim(coalesce(p_email,''))); if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise invalid_parameter_value using message='Introduce un correo válido.'; end if;
   if v_email=(select lower(email) from auth.users where id=v_uid) then raise invalid_parameter_value using message='No puedes invitarte a ti mismo.'; end if;
   if p_role not in('admin','editor','viewer') then raise invalid_parameter_value using message='Rol no válido.'; end if;
   v_role:=p_role::petlink.membership_role; v_token:=encode(extensions.gen_random_bytes(24),'hex');
   insert into petlink.pet_family_invites(pet_id,email,role,token_hash,invited_by) values(p_pet_id,v_email,v_role,encode(extensions.digest(v_token,'sha256'),'hex'),v_uid);
   insert into petlink.audit_events(actor_user_id,event_type,event_data) values((select id from petlink.app_users where id=v_uid),'family_invitation_created',jsonb_build_object('pet_id',p_pet_id,'email',v_email,'role',p_role));
   return jsonb_build_object('success',true,'invite_code',v_token,'expires_in_days',7);
  elsif p_action='revoke' then update petlink.pet_family_invites set revoked_at=now() where pet_id=p_pet_id and id=nullif(p_token,'')::uuid and accepted_at is null and revoked_at is null; return jsonb_build_object('success',true);
  else
   delete from petlink.pet_family_members where pet_id=p_pet_id and user_id=nullif(p_token,'')::uuid;
   insert into petlink.audit_events(actor_user_id,event_type,event_data) values((select id from petlink.app_users where id=v_uid),'family_member_removed',jsonb_build_object('pet_id',p_pet_id,'member_user_id',nullif(p_token,'')::uuid));
   return jsonb_build_object('success',true);
  end if;
 end if;
 raise invalid_parameter_value using message='Acción familiar no válida.';
end $$;
revoke all on function public.huellik_family_v1(text,uuid,text,text,text) from public,anon;
grant execute on function public.huellik_family_v1(text,uuid,text,text,text) to authenticated;