-- HUËLLIK owner-only user directory v1
-- Read-only. Returns only fields needed for support and account overview.
create or replace function public.huellik_admin_users_v1(
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
  v_total bigint;
  v_rows jsonb;
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

  if char_length(v_query) > 80 then
    raise invalid_parameter_value using message = 'Search query too long';
  end if;

  select count(*)
    into v_total
    from petlink.app_users u
   where v_query = ''
      or strpos(lower(u.email), v_query) > 0
      or strpos(lower(u.display_name), v_query) > 0;

  select coalesce(jsonb_agg(to_jsonb(page_row) order by page_row.created_at desc), '[]'::jsonb)
    into v_rows
    from (
      select
        u.id,
        u.email,
        u.display_name,
        u.email_verified_at is not null as email_verified,
        u.created_at,
        (select count(*)::integer
           from petlink.pet_members pm
          where pm.user_id = u.id) as pet_count,
        (select count(*)::integer
           from petlink.orders o
          where o.buyer_user_id = u.id) as order_count,
        latest.plan as subscription_plan,
        latest.status as subscription_status,
        latest.billing_interval as subscription_interval,
        exists(select 1 from petlink.admin_users a where a.user_id = u.id and a.role = 'owner') as is_owner
      from petlink.app_users u
      left join lateral (
        select s.plan::text as plan, s.status::text as status, s.billing_interval
          from petlink.subscriptions s
         where s.user_id = u.id
         order by s.created_at desc
         limit 1
      ) latest on true
      where v_query = ''
         or strpos(lower(u.email), v_query) > 0
         or strpos(lower(u.display_name), v_query) > 0
      order by u.created_at desc, u.id
      limit v_limit offset v_offset
    ) page_row;

  return jsonb_build_object(
    'users', v_rows,
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset
  );
end;
$function$;

revoke all on function public.huellik_admin_users_v1(text,integer,integer) from public;
revoke all on function public.huellik_admin_users_v1(text,integer,integer) from anon;
grant execute on function public.huellik_admin_users_v1(text,integer,integer) to authenticated;
