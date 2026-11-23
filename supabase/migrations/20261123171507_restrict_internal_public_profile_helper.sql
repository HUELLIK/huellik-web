-- Only the SECURITY DEFINER resolver should call this internal profile builder.
revoke all on function public.get_public_pet_profile(uuid) from public,anon,authenticated;
