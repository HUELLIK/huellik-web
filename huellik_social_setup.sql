-- HUËLLIK Social: saludos entre mascotas
create table if not exists public.pet_greetings (
  id uuid primary key default gen_random_uuid(),
  sender_pet_id uuid not null references public.pets(id) on delete cascade,
  target_pet_id uuid not null references public.pets(id) on delete cascade,
  sender_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint pet_greetings_no_self check (sender_pet_id <> target_pet_id),
  constraint pet_greetings_one_per_pair unique (sender_pet_id, target_pet_id)
);
alter table public.pet_greetings enable row level security;
grant select on public.pet_greetings to authenticated;
drop policy if exists "Pet families can view greetings involving their pets" on public.pet_greetings;
create policy "Pet families can view greetings involving their pets"
on public.pet_greetings for select to authenticated
using (
  exists (select 1 from public.pets p where p.id = sender_pet_id and p.owner_id = (select auth.uid()))
  or exists (select 1 from public.pets p where p.id = target_pet_id and p.owner_id = (select auth.uid()))
);
create or replace function public.send_pet_greeting(p_target_public_id uuid, p_sender_pet_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_target_pet_id uuid;
  v_inserted integer := 0;
  v_count integer := 0;
begin
  if v_user_id is null then return jsonb_build_object('success', false, 'message', 'Inicia sesión para enviar un saludo.'); end if;
  if not exists (select 1 from public.pets s where s.id = p_sender_pet_id and s.owner_id = v_user_id) then
    return jsonb_build_object('success', false, 'message', 'No puedes enviar saludos desde esa mascota.');
  end if;
  select t.id into v_target_pet_id from public.pets t
  where t.public_id = p_target_public_id and t.is_public = true and t.is_lost = false;
  if v_target_pet_id is null then return jsonb_build_object('success', false, 'message', 'Esta mascota no está disponible para recibir saludos.'); end if;
  if v_target_pet_id = p_sender_pet_id then return jsonb_build_object('success', false, 'message', 'Elige otra mascota para enviar el saludo.'); end if;
  insert into public.pet_greetings(sender_pet_id, target_pet_id, sender_user_id)
  values (p_sender_pet_id, v_target_pet_id, v_user_id)
  on conflict (sender_pet_id, target_pet_id) do nothing;
  get diagnostics v_inserted = row_count;
  select count(*)::integer into v_count from public.pet_greetings g where g.target_pet_id = v_target_pet_id;
  return jsonb_build_object('success', true, 'already_sent', v_inserted = 0, 'greeting_count', v_count);
end;
$function$;
revoke execute on function public.send_pet_greeting(uuid, uuid) from public, anon;
grant execute on function public.send_pet_greeting(uuid, uuid) to authenticated;

create or replace function public.get_public_pet_profile(p_public_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare v_result jsonb;
begin
  select jsonb_build_object(
    'public_id', p.public_id, 'name', p.name, 'species', p.species, 'breed', p.breed,
    'color', p.color, 'photo_url', p.photo_url, 'public_description', p.public_description,
    'is_lost', p.is_lost, 'show_medical_alerts', p.show_medical_alerts,
    'medical_alerts', case when p.show_medical_alerts then p.medical_alerts else null end,
    'greeting_count', (select count(*)::integer from public.pet_greetings g where g.target_pet_id = p.id),
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object('name', c.name, 'relationship', c.relationship,
        'phone', c.phone, 'email', c.email, 'whatsapp_enabled', c.whatsapp_enabled)
        order by c.sort_order, c.created_at)
      from public.pet_contacts c where c.pet_id = p.id and c.is_public = true
    ), '[]'::jsonb)
  ) into v_result
  from public.pets p where p.public_id = p_public_id and p.is_public = true;
  if v_result is null then return jsonb_build_object('error', 'not_found'); end if;
  return v_result;
end;
$function$;
