-- =====================================================================
-- FLEXO · Rutinas con nombre (fase 2 del selector de ejercicios)
-- Documenta las tablas y la función que YA existen en Supabase
-- (proyecto glomtdofnkayvwslxqko); se creó fuera de este repositorio.
-- Es idempotente: se puede ejecutar de nuevo sin romper nada.
-- =====================================================================

create table if not exists public.flexo_routines (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 60),
  created_at timestamptz not null default now()
);
create unique index if not exists flexo_routines_user_name_uq
  on public.flexo_routines (user_id, lower(btrim(name)));

create table if not exists public.flexo_routine_items (
  id         uuid primary key default gen_random_uuid(),
  routine_id uuid not null references public.flexo_routines(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  "position" int  not null check ("position" >= 0),
  name       text not null check (char_length(btrim(name)) between 1 and 80),
  category   text check (category is null or char_length(btrim(category)) between 1 and 30),
  created_at timestamptz not null default now()
);
create index if not exists flexo_routine_items_routine_idx
  on public.flexo_routine_items (routine_id, "position");

alter table public.flexo_routines enable row level security;
alter table public.flexo_routine_items enable row level security;

drop policy if exists own_flexo_routines on public.flexo_routines;
create policy own_flexo_routines on public.flexo_routines
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Un ejercicio de rutina solo puede colgar de una rutina del mismo usuario
drop policy if exists own_flexo_routine_items on public.flexo_routine_items;
create policy own_flexo_routine_items on public.flexo_routine_items
  for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.flexo_routines r
                 where r.id = routine_id and r.user_id = auth.uid())
  );

revoke all on public.flexo_routines, public.flexo_routine_items from anon, public;
grant select, insert, update, delete on public.flexo_routines, public.flexo_routine_items to authenticated;

-- Crear o editar una rutina con sus ejercicios en UNA sola transacción.
-- p_routine_id nulo o vacío = rutina nueva. El orden del arreglo p_items es la posición.
CREATE OR REPLACE FUNCTION public.flexo_save_routine(p_routine_id text, p_name text, p_items jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_id   uuid;
  v_name text := btrim(coalesce(p_name, ''));
  v_n    int  := 0;
begin
  if v_uid is null then
    raise exception 'Sesión no iniciada' using errcode = '28000';
  end if;
  if char_length(v_name) not between 1 and 60 then
    raise exception 'El nombre de la rutina debe tener entre 1 y 60 caracteres' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) is distinct from 'array' then
    raise exception 'p_items debe ser un arreglo' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 50 then
    raise exception 'Una rutina admite hasta 50 ejercicios' using errcode = '22023';
  end if;

  if nullif(btrim(coalesce(p_routine_id, '')), '') is null then
    insert into public.flexo_routines (user_id, name) values (v_uid, v_name) returning id into v_id;
  else
    begin
      v_id := p_routine_id::uuid;
    exception when invalid_text_representation then
      raise exception 'Id de rutina inválido' using errcode = '22023';
    end;
    perform 1 from public.flexo_routines where id = v_id and user_id = v_uid for update;
    if not found then
      raise exception 'Rutina no encontrada o sin permiso' using errcode = 'P0002';
    end if;
    update public.flexo_routines set name = v_name where id = v_id and user_id = v_uid;
    delete from public.flexo_routine_items where routine_id = v_id and user_id = v_uid;
  end if;

  insert into public.flexo_routine_items (routine_id, user_id, position, name, category)
  select v_id, v_uid, (e.ord - 1)::int, btrim(e.elem->>'name'),
         nullif(btrim(coalesce(e.elem->>'category', '')), '')
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) with ordinality as e(elem, ord);
  get diagnostics v_n = row_count;

  return jsonb_build_object('id', v_id, 'items', v_n);
end;
$function$;

revoke all on function public.flexo_save_routine(text, text, jsonb) from public, anon;
grant execute on function public.flexo_save_routine(text, text, jsonb) to authenticated;
