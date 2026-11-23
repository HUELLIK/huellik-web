create or replace function public.resolve_public_pet_profile(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tag petlink.tag_links%rowtype;
  v_public_id uuid;
begin
  if p_code is null or length(trim(p_code)) = 0 or length(trim(p_code)) > 200 then
    return jsonb_build_object('error','not_found');
  end if;
  select * into v_tag from petlink.tag_links t where t.public_code = trim(p_code);
  if found then
    if v_tag.status not in ('active','lost') or v_tag.public_pet_id is null then
      return jsonb_build_object('error','not_found');
    end if;
    select p.public_id into v_public_id
    from public.pets p
    where p.id = v_tag.public_pet_id and p.is_public = true;
    if v_public_id is null then return jsonb_build_object('error','not_found'); end if;
    return public.get_public_pet_profile(v_public_id);
  end if;
  return public.resolve_public_pet_profile_legacy(p_code);
end;
$function$;
revoke all on function public.resolve_public_pet_profile_legacy(text) from public, anon, authenticated;
revoke all on function public.resolve_public_pet_profile(text) from public;
grant execute on function public.resolve_public_pet_profile(text) to anon, authenticated;