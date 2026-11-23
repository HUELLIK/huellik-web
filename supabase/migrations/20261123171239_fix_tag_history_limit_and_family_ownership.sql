create or replace function public.huellik_admin_tag_history_v1(p_tag_id uuid,p_limit integer default 30)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_result jsonb;
begin
 if v_user is null or not exists(select 1 from petlink.admin_users a where a.user_id=v_user and a.role='owner') then raise insufficient_privilege using message='Acceso de administrador requerido.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('event_type',x.event_type,'event_data',x.event_data,'created_at',x.created_at,'actor',x.actor) order by x.created_at desc),'[]'::jsonb) into v_result
 from (select e.event_type,e.event_data,e.created_at,u.display_name actor from petlink.audit_events e left join petlink.app_users u on u.id=e.actor_user_id where e.event_data->>'tag_id'=p_tag_id::text order by e.created_at desc limit greatest(1,least(coalesce(p_limit,30),100))) x;
 return jsonb_build_object('events',v_result);
end $$;
revoke all on function public.huellik_admin_tag_history_v1(uuid,integer) from public,anon;
grant execute on function public.huellik_admin_tag_history_v1(uuid,integer) to authenticated;
create or replace function public.huellik_prevent_pet_owner_change()
returns trigger language plpgsql security invoker set search_path=''
as $$ begin
 if new.owner_id is distinct from old.owner_id and old.owner_id is distinct from auth.uid() then raise insufficient_privilege using message='Solo el propietario actual puede transferir la propiedad.'; end if;
 return new;
end $$;
drop trigger if exists pets_prevent_owner_change on public.pets;
create trigger pets_prevent_owner_change before update of owner_id on public.pets for each row execute function public.huellik_prevent_pet_owner_change();
revoke all on function public.huellik_prevent_pet_owner_change() from public,anon,authenticated;
