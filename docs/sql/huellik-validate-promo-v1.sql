-- HUËLLIK: server-side promotional code eligibility validation v1
-- Does not calculate the cart total and does not reserve a redemption.
-- Checkout must calculate prices on the server and re-check atomically when reserving.

create or replace function public.huellik_validate_promo_v1(
  p_code text,
  p_scope text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_promo petlink.promo_codes%rowtype;
  v_now timestamptz := now();
  v_global_count bigint;
  v_user_count bigint;
  v_has_prior_purchase boolean;
begin
  if v_user_id is null then
    raise insufficient_privilege using message = 'Authentication required';
  end if;

  if p_code is null or char_length(trim(p_code)) not between 3 and 40
     or p_scope is null
     or p_scope not in ('plus_monthly','plus_annual','tag_metal','tag_flex') then
    raise invalid_parameter_value using message = 'Invalid promotion request';
  end if;

  select *
    into v_promo
    from petlink.promo_codes p
   where upper(p.code) = upper(trim(p_code))
   limit 1;

  -- Deliberately return the same response for unknown, inactive and ineligible codes.
  if not found or not v_promo.active
     or v_promo.starts_at > v_now
     or (v_promo.expires_at is not null and v_promo.expires_at <= v_now)
     or not ('all' = any(v_promo.applies_to) or p_scope = any(v_promo.applies_to)) then
    return jsonb_build_object('valid', false, 'message', 'El código no es válido para esta compra.');
  end if;

  if v_promo.first_time_only then
    select exists (
      select 1
        from petlink.orders o
       where o.buyer_user_id = v_user_id
         and o.status in ('paid','processing','sent_to_supplier','shipped','delivered')
      union all
      select 1
        from petlink.subscriptions s
       where s.user_id = v_user_id
         and s.status in ('trialing','active','past_due')
    ) into v_has_prior_purchase;

    if v_has_prior_purchase then
      return jsonb_build_object('valid', false, 'message', 'El código no es válido para esta compra.');
    end if;
  end if;

  select count(*)
    into v_global_count
    from petlink.promo_redemptions r
   where r.promo_code_id = v_promo.id
     and (
       r.status = 'redeemed'
       or (r.status = 'reserved' and r.reserved_at > v_now - interval '30 minutes')
     );

  if v_promo.max_redemptions is not null and v_global_count >= v_promo.max_redemptions then
    return jsonb_build_object('valid', false, 'message', 'El código no es válido para esta compra.');
  end if;

  select count(*)
    into v_user_count
    from petlink.promo_redemptions r
   where r.promo_code_id = v_promo.id
     and r.user_id = v_user_id
     and (
       r.status = 'redeemed'
       or (r.status = 'reserved' and r.reserved_at > v_now - interval '30 minutes')
     );

  if v_user_count >= v_promo.max_redemptions_per_user then
    return jsonb_build_object('valid', false, 'message', 'El código no es válido para esta compra.');
  end if;

  return jsonb_build_object(
    'valid', true,
    'code', v_promo.code,
    'discount_type', v_promo.discount_type,
    'discount_value', v_promo.discount_value,
    'currency', v_promo.currency,
    'scope', p_scope,
    'message', 'Código válido. El descuento definitivo se calculará al preparar el pago.'
  );
end;
$function$;

revoke all on function public.huellik_validate_promo_v1(text,text) from public;
revoke all on function public.huellik_validate_promo_v1(text,text) from anon;
grant execute on function public.huellik_validate_promo_v1(text,text) to authenticated;
