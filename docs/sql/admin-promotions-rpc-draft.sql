-- HUËLLIK admin promotions RPC v1
-- DRAFT ONLY. Do not execute until reviewed together with the promo tables migration.
-- Uses the caller JWT; no service_role and no direct petlink schema exposure.

create or replace function public.huellik_admin_promotions_v1(
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_id uuid;
  v_code text;
  v_type text;
  v_value numeric(10,2);
  v_currency text;
  v_scopes text[];
  v_starts timestamptz;
  v_expires timestamptz;
  v_max integer;
  v_per_user integer;
  v_first boolean;
  v_active boolean;
  v_description text;
  v_result jsonb;
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

  if p_action = 'list' then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', p.id, 'code', p.code, 'description', p.description,
        'discount_type', p.discount_type, 'discount_value', p.discount_value,
        'currency', p.currency, 'applies_to', p.applies_to,
        'starts_at', p.starts_at, 'expires_at', p.expires_at,
        'max_redemptions', p.max_redemptions,
        'max_redemptions_per_user', p.max_redemptions_per_user,
        'first_time_only', p.first_time_only, 'active', p.active,
        'created_at', p.created_at,
        'reserved_count', coalesce(r.reserved_count, 0),
        'redeemed_count', coalesce(r.redeemed_count, 0)
      ) order by p.created_at desc
    ), '[]'::jsonb)
    into v_result
    from petlink.promo_codes p
    left join lateral (
      select
        count(*) filter (where status = 'reserved' and reserved_at > now() - interval '30 minutes')::integer as reserved_count,
        count(*) filter (where status = 'redeemed')::integer as redeemed_count
      from petlink.promo_redemptions pr
      where pr.promo_code_id = p.id
    ) r on true;
    return jsonb_build_object('promotions', v_result);
  end if;

  if p_action not in ('create', 'update', 'deactivate') then
    raise invalid_parameter_value using message = 'Unsupported action';
  end if;

  if p_action <> 'create' then
    v_id := nullif(p_payload->>'id', '')::uuid;
    if v_id is null then
      raise invalid_parameter_value using message = 'Promotion id is required';
    end if;
  end if;

  if p_action = 'deactivate' then
    update petlink.promo_codes set active = false, updated_at = now()
    where id = v_id;
    if not found then
      raise no_data_found using message = 'Promotion not found';
    end if;
    return jsonb_build_object('ok', true, 'id', v_id, 'active', false);
  end if;

  v_code := upper(trim(coalesce(p_payload->>'code', '')));
  v_type := coalesce(p_payload->>'discount_type', '');
  v_value := nullif(p_payload->>'discount_value', '')::numeric;
  v_currency := upper(coalesce(p_payload->>'currency', 'EUR'));
  v_description := nullif(trim(p_payload->>'description'), '');
  v_starts := coalesce(nullif(p_payload->>'starts_at', '')::timestamptz, now());
  v_expires := nullif(p_payload->>'expires_at', '')::timestamptz;
  v_max := nullif(p_payload->>'max_redemptions', '')::integer;
  v_per_user := coalesce(nullif(p_payload->>'max_redemptions_per_user', '')::integer, 1);
  v_first := coalesce((p_payload->>'first_time_only')::boolean, false);
  v_active := coalesce((p_payload->>'active')::boolean, true);

  if char_length(v_code) not between 3 and 40 or v_code !~ '^[A-Z0-9_-]+$' then
    raise invalid_parameter_value using message = 'Invalid promotion code';
  end if;
  if v_type not in ('percent', 'fixed') or v_value is null or v_value <= 0 then
    raise invalid_parameter_value using message = 'Invalid discount';
  end if;
  if v_type = 'percent' and v_value > 100 then
    raise invalid_parameter_value using message = 'Percentage cannot exceed 100';
  end if;
  if v_type = 'fixed' and v_currency <> 'EUR' then
    raise invalid_parameter_value using message = 'Only EUR is currently supported';
  end if;
  if v_per_user < 1 or (v_max is not null and v_max < 1) then
    raise invalid_parameter_value using message = 'Invalid redemption limits';
  end if;
  if v_expires is not null and v_expires <= v_starts then
    raise invalid_parameter_value using message = 'Expiry must be after start';
  end if;

  select coalesce(array_agg(value), array[]::text[])
  into v_scopes
  from jsonb_array_elements_text(coalesce(p_payload->'applies_to', '["all"]'::jsonb)) as scope(value);
  if cardinality(v_scopes) = 0 or exists (
    select 1 from unnest(v_scopes) s
    where s not in ('all','plus_monthly','plus_annual','tag_metal','tag_flex')
  ) then
    raise invalid_parameter_value using message = 'Invalid promotion scope';
  end if;
  if 'all' = any(v_scopes) and cardinality(v_scopes) > 1 then
    raise invalid_parameter_value using message = 'Scope all cannot be combined';
  end if;

  if p_action = 'create' then
    insert into petlink.promo_codes(
      code, description, discount_type, discount_value, currency, applies_to,
      starts_at, expires_at, max_redemptions, max_redemptions_per_user,
      first_time_only, active, created_by
    ) values (
      v_code, v_description, v_type, v_value, v_currency, v_scopes,
      v_starts, v_expires, v_max, v_per_user, v_first, v_active, v_user_id
    ) returning id into v_id;
  else
    if exists (select 1 from petlink.promo_redemptions where promo_code_id = v_id) then
      if exists (
        select 1 from petlink.promo_codes p
        where p.id = v_id and (
          p.code <> v_code
          or p.discount_type <> v_type
          or p.discount_value <> v_value
          or p.currency <> v_currency
          or p.applies_to <> v_scopes
        )
      ) then
        raise check_violation using message = 'Discount terms cannot change after a redemption exists';
      end if;
    end if;
    update petlink.promo_codes set
      code = v_code, description = v_description, discount_type = v_type,
      discount_value = v_value, currency = v_currency, applies_to = v_scopes,
      starts_at = v_starts, expires_at = v_expires, max_redemptions = v_max,
      max_redemptions_per_user = v_per_user, first_time_only = v_first,
      active = v_active, updated_at = now()
    where id = v_id;
    if not found then
      raise no_data_found using message = 'Promotion not found';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$;

revoke all on function public.huellik_admin_promotions_v1(text, jsonb) from public;
revoke all on function public.huellik_admin_promotions_v1(text, jsonb) from anon;
grant execute on function public.huellik_admin_promotions_v1(text, jsonb) to authenticated;
