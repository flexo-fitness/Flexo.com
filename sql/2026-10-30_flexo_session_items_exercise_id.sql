-- =====================================================================
-- FLEXO · Migración aplicada en Supabase:
-- flexo_session_items_exercise_id_vinculo_y_relleno  (fase 3 del selector de ejercicios)
-- Proyecto: glomtdofnkayvwslxqko
-- Vincula cada serie a un ejercicio de la biblioteca (exercise_id) y rellena el historial.
-- El relleno (paso 5) es un DATO de una sola vez: ya se ejecutó. Es idempotente
-- (on conflict do nothing), pero no hace falta repetirlo.
-- =====================================================================

-- 1) Llave de comparación de nombres: ignora mayúsculas, tildes (y ñ), espacios sobrantes
create or replace function public.flexo_name_key(t text)
returns text
language sql
immutable
set search_path = public
as $$
  select translate(lower(btrim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g'))), 'áéíóúüñ', 'aeiouun')
$$;

-- 2) Columna y vínculo (si se borra el ejercicio de la biblioteca, la serie se conserva sin vínculo)
alter table public.flexo_session_items
  add column if not exists exercise_id uuid references public.flexo_exercises(id) on delete set null;
create index if not exists flexo_session_items_exercise_idx
  on public.flexo_session_items (exercise_id) where exercise_id is not null;

-- 3) Al guardar una serie: vincula por nombre y nunca acepta el ejercicio de otro usuario
create or replace function public.flexo_session_items_link_exercise()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.exercise_id is not null
     and not exists (select 1 from public.flexo_exercises e
                      where e.id = new.exercise_id and e.user_id = new.user_id) then
    new.exercise_id := null;
  end if;
  if new.exercise_id is null
     or (tg_op = 'UPDATE' and new.name is distinct from old.name
         and new.exercise_id is not distinct from old.exercise_id) then
    new.exercise_id := (select e.id from public.flexo_exercises e
                         where e.user_id = new.user_id
                           and public.flexo_name_key(e.name) = public.flexo_name_key(new.name)
                         order by e.created_at, e.id limit 1);
  end if;
  return new;
end;
$$;

drop trigger if exists flexo_session_items_link on public.flexo_session_items;
create trigger flexo_session_items_link
  before insert or update of name, exercise_id on public.flexo_session_items
  for each row execute function public.flexo_session_items_link_exercise();

-- 4) Al agregar un ejercicio a la biblioteca: vincula las series anteriores con ese nombre
create or replace function public.flexo_exercises_link_items()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  update public.flexo_session_items i
     set exercise_id = new.id
   where i.user_id = new.user_id
     and i.exercise_id is null
     and public.flexo_name_key(i.name) = public.flexo_name_key(new.name);
  return null;
end;
$$;

drop trigger if exists flexo_exercises_link on public.flexo_exercises;
create trigger flexo_exercises_link
  after insert on public.flexo_exercises
  for each row execute function public.flexo_exercises_link_items();

-- 5) Relleno del historial (una sola vez): crea en la biblioteca de cada usuario los ejercicios
--    ya escritos (categoría del catálogo si el nombre coincide; si no, 'otro') y vincula sus series
with cat(category, name) as (values
 ('pecho','Press de banca plano'),('pecho','Press de banca inclinado'),('pecho','Press con mancuernas'),('pecho','Aperturas con mancuernas'),('pecho','Cruces en polea'),('pecho','Fondos en paralelas'),('pecho','Flexiones de pecho'),
 ('espalda','Dominadas'),('espalda','Jalón al pecho'),('espalda','Remo con barra'),('espalda','Remo con mancuerna'),('espalda','Remo en polea baja'),('espalda','Remo en máquina'),('espalda','Peso muerto convencional'),
 ('hombro','Press militar con barra'),('hombro','Press de hombros con mancuernas'),('hombro','Elevaciones laterales'),('hombro','Elevaciones frontales'),('hombro','Pájaros (vuelos posteriores)'),('hombro','Face pull'),
 ('brazo','Curl con barra'),('brazo','Curl con mancuernas'),('brazo','Curl predicador'),('brazo','Curl araña'),('brazo','Curl martillo'),('brazo','Extensión de tríceps en polea'),('brazo','Press francés'),('brazo','Fondos para tríceps'),('brazo','Patada de tríceps'),
 ('pierna','Sentadilla'),('pierna','Prensa de piernas'),('pierna','Extensión de cuádriceps'),('pierna','Curl femoral'),('pierna','Peso muerto rumano'),('pierna','Zancadas'),('pierna','Sentadilla búlgara'),('pierna','Elevación de talones'),
 ('gluteo','Hip thrust'),('gluteo','Puente de glúteo'),('gluteo','Patada de glúteo en polea'),('gluteo','Abducción de cadera en máquina'),('gluteo','Sentadilla sumo'),
 ('core','Plancha'),('core','Plancha lateral'),('core','Crunch abdominal'),('core','Elevación de piernas'),('core','Rueda abdominal'),('core','Giro ruso')),
src as (
  select i.user_id,
         public.flexo_name_key(i.name) as k,
         mode() within group (order by btrim(regexp_replace(i.name, '\s+', ' ', 'g'))) as spelling
    from public.flexo_session_items i
   where public.flexo_name_key(i.name) <> ''
   group by 1, 2),
pick as (
  select s.user_id,
         left(coalesce(c.name, s.spelling), 80) as name,
         coalesce(c.category, 'otro') as category
    from src s
    left join cat c on public.flexo_name_key(c.name) = s.k)
insert into public.flexo_exercises (user_id, name, category)
select user_id, name, category from pick
on conflict do nothing;

-- Vínculo final por si alguna serie quedó sin enlazar
update public.flexo_session_items i
   set exercise_id = e.id
  from public.flexo_exercises e
 where i.exercise_id is null
   and e.user_id = i.user_id
   and public.flexo_name_key(e.name) = public.flexo_name_key(i.name);
