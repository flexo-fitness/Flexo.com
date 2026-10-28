-- =====================================================================
-- FLEXO · Migración aplicada en Supabase: flexo_exercises_biblioteca_de_ejercicios
-- Proyecto: glomtdofnkayvwslxqko
-- Biblioteca de ejercicios por usuario (fase 1 del selector de ejercicios).
-- =====================================================================

create table public.flexo_exercises (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 80),
  category   text not null check (char_length(btrim(category)) between 1 and 30),
  created_at timestamptz not null default now()
);

-- Un usuario no puede repetir el mismo nombre (sin importar mayúsculas ni espacios)
create unique index flexo_exercises_user_name_uq
  on public.flexo_exercises (user_id, lower(btrim(name)));

alter table public.flexo_exercises enable row level security;

create policy own_flexo_exercises on public.flexo_exercises
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Solo usuarios con sesión iniciada; anon no tiene acceso
revoke all on public.flexo_exercises from anon, public;
grant select, insert, update, delete on public.flexo_exercises to authenticated;
