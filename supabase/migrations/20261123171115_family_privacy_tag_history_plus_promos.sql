-- Family sharing, tag history, privacy boundaries and Plus promo reservations.
create table if not exists petlink.pet_family_members (
 pet_id uuid not null references public.pets(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role petlink.membership_role not null default 'viewer',
 invited_by uuid references auth.users(id) on delete set null,
 accepted_at timestamptz not null default now(), created_at timestamptz not null default now(),
 primary key(pet_id,user_id), constraint pet_family_not_owner check(role<>'owner')
);
create table if not exists petlink.pet_family_invites (
 id uuid primary key default gen_random_uuid(),
 pet_id uuid not null references public.pets(id) on delete cascade,
 email text not null, role petlink.membership_role not null default 'viewer',
 token_hash text not null unique, invited_by uuid not null references auth.users(id) on delete cascade,
 expires_at timestamptz not null default(now()+interval '7 days'),
 accepted_at timestamptz, revoked_at timestamptz, created_at timestamptz not null default now(),
 constraint pet_family_invite_role check(role in('admin','editor','viewer'))
);
alter table petlink.pet_family_members enable row level security;
alter table petlink.pet_family_invites enable row level security;
revoke all on petlink.pet_family_members,petlink.pet_family_invites from anon,authenticated;

create or replace function public.huellik_family_can_edit_pet(p_pet_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.pets p where p.id=p_pet_id and p.owner_id=auth.uid())
 or exists(select 1 from petlink.pet_family_members m where m.pet_id=p_pet_id and m.user_id=auth.uid() and m.role in('admin','editor')); $$;
revoke all on function public.huellik_family_can_edit_pet(uuid) from public,anon,authenticated;
grant execute on function public.huellik_family_can_edit_pet(uuid) to authenticated;

drop policy if exists pets_select_family on public.pets;
create policy pets_select_family on public.pets for select to authenticated using(exists(select 1 from petlink.pet_family_members m where m.pet_id=id and m.user_id=auth.uid()));
drop policy if exists pets_update_family on public.pets;
create policy pets_update_family on public.pets for update to authenticated using(public.huellik_family_can_edit_pet(id))
with check(owner_id=auth.uid() or exists(select 1 from petlink.pet_family_members m where m.pet_id=id and m.user_id=auth.uid() and m.role in('admin','editor')));
drop policy if exists contacts_select_family on public.pet_contacts;
create policy contacts_select_family on public.pet_contacts for select to authenticated using(exists(select 1 from petlink.pet_family_members m where m.pet_id=pet_id and m.user_id=auth.uid()));
drop policy if exists contacts_insert_family on public.pet_contacts;
create policy contacts_insert_family on public.pet_contacts for insert to authenticated with check(public.huellik_family_can_edit_pet(pet_id));
drop policy if exists contacts_update_family on public.pet_contacts;
create policy contacts_update_family on public.pet_contacts for update to authenticated using(public.huellik_family_can_edit_pet(pet_id)) with check(public.huellik_family_can_edit_pet(pet_id));
drop policy if exists contacts_delete_family on public.pet_contacts;
create policy contacts_delete_family on public.pet_contacts for delete to authenticated using(public.huellik_family_can_edit_pet(pet_id));

create or replace function public.huellik_family_v1(p_action text,p_pet_id uuid default null,p_email text default null,p_role text default 'viewer',p_token text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_pet public.pets%rowtype; v_token text; v_email text; v_role petlink.membership_role; v_member jsonb;
begin
 if v_uid is null then raise insufficient_privilege using message='Inicia sesión.'; end if;
 if p_action='accept' then
  if p_token is null or length(p_token)<20 then raise invalid_parameter_value using message='Código de invitación no válido.'; end if;
  select p.* into v_pet from public.pets p join petlink.pet_family_invites i on i.pet_id=p.id
   where i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and i.accepted_at is null and i.revoked_at is null and i.expires_at>now()
   and lower(i.email)=(select lower(email) from auth.users where id=v_uid) limit 1;
  if not found then raise insufficient_privilege using message='Invitación caducada, revocada o destinada a otro correo.'; end if;
  insert into petlink.pet_family_members(pet_id,user_id,role,invited_by)
   select i.pet_id,v_uid,i.role,i.invited_by from petlink.pet_family_invites i where i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
   on conflict(pet_id,user_id) do update set role=excluded.role;
  update petlink.pet_family_invites set accepted_at=now() where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
  return jsonb_build_object('success',true,'message','Invitación aceptada.');
 end if;
 if p_action='list' then
  if p_pet_id is null then
   return jsonb_build_object('pets',coalesce((select jsonb_agg(jsonb_build_object('pet_id',p.id,'pet_name',p.name,'role','owner')) from public.pets p where p.owner_id=v_uid),'[]'::jsonb)
   ||coalesce((select jsonb_agg(jsonb_build_object('pet_id',p.id,'pet_name',p.name,'role',m.role::text)) from petlink.pet_family_members m join public.pets p on p.id=m.pet_id where m.user_id=v_uid),'[]'::jsonb));
  end if;
  if not exists(select 1 from public.pets p where p.id=p_pet_id and (p.owner_id=v_uid or exists(select 1 from petlink.pet_family_members m where m.pet_id=p.id and m.user_id=v_uid))) then raise insufficient_privilege using message='No tienes acceso a esta mascota.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('email',u.email,'role',m.role::text,'user_id',m.user_id)),'[]'::jsonb) into v_member from petlink.pet_family_members m join auth.users u on u.id=m.user_id where m.pet_id=p_pet_id;
  return jsonb_build_object('members',v_member,'is_owner',exists(select 1 from public.pets p where p.id=p_pet_id and p.owner_id=v_uid));
 end if;
 if p_action in('invite','revoke','remove') then
  if p_pet_id is null or not exists(select 1 from public.pets p where p.id=p_pet_id and p.owner_id=v_uid) then raise insufficient_privilege using message='Solo la persona propietaria puede gestionar invitaciones y miembros.'; end if;
  if p_action='invite' then
   v_email:=lower(trim(coalesce(p_email,'')));
   if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise invalid_parameter_value using message='Introduce un correo válido.'; end if;
   if v_email=(select lower(email) from auth.users where id=v_uid) then raise invalid_parameter_value using message='No puedes invitarte a ti mismo.'; end if;
   if p_role not in('admin','editor','viewer') then raise invalid_parameter_value using message='Rol no válido.'; end if;
   v_role:=p_role::petlink.membership_role; v_token:=encode(extensions.gen_random_bytes(24),'hex');
   insert into petlink.pet_family_invites(pet_id,email,role,token_hash,invited_by) values(p_pet_id,v_email,v_role,encode(extensions.digest(v_token,'sha256'),'hex'),v_uid);
   insert into petlink.audit_events(actor_user_id,event_type,event_data) values((select id from petlink.app_users where id=v_uid),'family_invitation_created',jsonb_build_object('pet_id',p_pet_id,'email',v_email,'role',p_role));
   return jsonb_build_object('success',true,'invite_code',v_token,'expires_in_days',7);
  elsif p_action='revoke' then
   update petlink.pet_family_invites set revoked_at=now() where pet_id=p_pet_id and id=nullif(p_token,'')::uuid and accepted_at is null and revoked_at is null;
   return jsonb_build_object('success',true);
  else
   delete from petlink.pet_family_members where pet_id=p_pet_id and user_id=nullif(p_token,'')::uuid;
   return jsonb_build_object('success',true);
  end if;
 end if;
 raise invalid_parameter_value using message='Acción familiar no válida.';
end $$;
revoke all on function public.huellik_family_v1(text,uuid,text,text,text) from public,anon;
grant execute on function public.huellik_family_v1(text,uuid,text,text,text) to authenticated;

create or replace function public.huellik_admin_tag_history_v1(p_tag_id uuid,p_limit integer default 30)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_result jsonb;
begin
 if v_user is null or not exists(select 1 from petlink.admin_users a where a.user_id=v_user and a.role='owner') then raise insufficient_privilege using message='Acceso de administrador requerido.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('event_type',e.event_type,'event_data',e.event_data,'created_at',e.created_at,'actor',u.display_name) order by e.created_at desc),'[]'::jsonb)
 into v_result from petlink.audit_events e left join petlink.app_users u on u.id=e.actor_user_id where e.event_data->>'tag_id'=p_tag_id::text limit greatest(1,least(coalesce(p_limit,30),100));
 return jsonb_build_object('events',v_result);
end $$;
revoke all on function public.huellik_admin_tag_history_v1(uuid,integer) from public,anon;
grant execute on function public.huellik_admin_tag_history_v1(uuid,integer) to authenticated;

alter table public.plus_requests add column if not exists promo_redemption_id uuid references petlink.promo_redemptions(id) on delete set null;
alter table public.plus_requests add column if not exists discounted_price_eur numeric(10,2);
create or replace function public.huellik_apply_plus_promo_v1(p_code text,p_interval text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_promo petlink.promo_codes%rowtype; v_base numeric(10,2); v_discount numeric(10,2); v_redemption uuid; v_global bigint; v_user bigint;
begin
 if v_uid is null then raise insufficient_privilege using message='Inicia sesión para aplicar el código.'; end if;
 if p_interval not in('monthly','annual') then raise invalid_parameter_value using message='Plan no válido.'; end if;
 v_base:=case when p_interval='monthly' then 1.99 else 19.99 end;
 select * into v_promo from petlink.promo_codes where upper(code)=upper(trim(p_code)) for update;
 if not found or not v_promo.active or v_promo.starts_at>now() or (v_promo.expires_at is not null and v_promo.expires_at<=now())
 or not('all'=any(v_promo.applies_to) or (case when p_interval='monthly' then 'plus_monthly' else 'plus_annual' end)=any(v_promo.applies_to)) then return jsonb_build_object('valid',false,'message','El código no es válido para este plan.'); end if;
 if v_promo.first_time_only and (exists(select 1 from petlink.orders where buyer_user_id=v_uid and status in('paid','processing','sent_to_supplier','shipped','delivered')) or exists(select 1 from petlink.subscriptions where user_id=v_uid and status in('trialing','active','past_due'))) then return jsonb_build_object('valid',false,'message','El código no es válido para este plan.'); end if;
 select count(*) into v_global from petlink.promo_redemptions where promo_code_id=v_promo.id and(status='redeemed' or(status='reserved' and reserved_at>now()-interval '30 minutes'));
 select count(*) into v_user from petlink.promo_redemptions where promo_code_id=v_promo.id and user_id=v_uid and(status='redeemed' or(status='reserved' and reserved_at>now()-interval '30 minutes'));
 if(v_promo.max_redemptions is not null and v_global>=v_promo.max_redemptions)or v_user>=v_promo.max_redemptions_per_user then return jsonb_build_object('valid',false,'message','El código ya ha alcanzado su límite de uso.'); end if;
 v_discount:=case when v_promo.discount_type='percent' then round(v_base*v_promo.discount_value/100,2) else least(v_base,v_promo.discount_value) end;
 insert into petlink.promo_redemptions(promo_code_id,user_id,status,discount_amount,currency,reserved_at) values(v_promo.id,v_uid,'reserved',v_discount,'EUR',now()) returning id into v_redemption;
 return jsonb_build_object('valid',true,'redemption_id',v_redemption,'code',v_promo.code,'base_price',v_base,'discount_amount',v_discount,'final_price',greatest(0,v_base-v_discount),'message','Código reservado durante 30 minutos. El cobro todavía no está conectado.');
end $$;
revoke all on function public.huellik_apply_plus_promo_v1(text,text) from public,anon;
grant execute on function public.huellik_apply_plus_promo_v1(text,text) to authenticated;
create or replace function public.huellik_release_plus_promo_v1(p_redemption_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$ begin
 if auth.uid() is null then raise insufficient_privilege using message='Inicia sesión.'; end if;
 update petlink.promo_redemptions set status='void',voided_at=now() where id=p_redemption_id and user_id=auth.uid() and status='reserved';
 return jsonb_build_object('success',true);
end $$;
revoke all on function public.huellik_release_plus_promo_v1(uuid) from public,anon;
grant execute on function public.huellik_release_plus_promo_v1(uuid) to authenticated;

create or replace function public.get_public_pet_profile(p_public_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_result jsonb;
begin
 select jsonb_build_object('name',p.name,'species',p.species,'breed',p.breed,'color',p.color,'public_description',p.public_description,'is_lost',p.is_lost,
 'show_medical_alerts',p.show_medical_alerts,'medical_alerts',case when p.show_medical_alerts then p.medical_alerts else null end,
 'contacts',coalesce((select jsonb_agg(jsonb_build_object('name',c.name,'relationship',c.relationship,'phone',c.phone,'email',c.email,'whatsapp_enabled',c.whatsapp_enabled) order by c.sort_order,c.created_at) from public.pet_contacts c where c.pet_id=p.id and c.is_public=true),'[]'::jsonb))
 into v_result from public.pets p where p.public_id=p_public_id and p.is_public=true;
 if v_result is null then return jsonb_build_object('error','not_found'); end if; return v_result;
end $$;
revoke all on function public.get_public_pet_profile(uuid) from public,anon,authenticated;
grant execute on function public.get_public_pet_profile(uuid) to authenticated;
revoke all on function public.resolve_public_pet_profile(text) from public,authenticated;
grant execute on function public.resolve_public_pet_profile(text) to anon,authenticated;
