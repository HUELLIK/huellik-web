-- HUËLLIK admin overview RPC — DRAFT ONLY
-- Apply only after reviewing in the development workflow.
-- This function returns aggregate counts only. It does not expose user or pet records.
-- The Edge Function calls it using the authenticated caller's JWT.
-- SECURITY DEFINER is narrowly required to read the private petlink schema;
-- authorization is checked against auth.uid() and petlink.admin_users on every call.

create or replace function public.huellik_admin_overview_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise insufficient_privilege using message = 'Authentication required';
  end if;

  if not exists (
    select 1
    from petlink.admin_users as admin
    where admin.user_id = v_user_id
      and admin.role = 'owner'
  ) then
    raise insufficient_privilege using message = 'Administrator access required';
  end if;

  return pg_catalog.jsonb_build_object(
    'users', (select count(*)::integer from petlink.app_users),
    'pets', (select count(*)::integer from petlink.pets),
    'identifiers', (select count(*)::integer from petlink.identifiers),
    'orders', (select count(*)::integer from petlink.orders),
    'subscriptions', (select count(*)::integer from petlink.subscriptions)
  );
end;
$function$;

revoke all on function public.huellik_admin_overview_v1() from public;
revoke all on function public.huellik_admin_overview_v1() from anon;
grant execute on function public.huellik_admin_overview_v1() to authenticated;
