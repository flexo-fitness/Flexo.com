-- =====================================================================
-- FLEXO · Migración aplicada en Supabase: flexo_create_session_atomica
-- Proyecto: glomtdofnkayvwslxqko
-- Crea una sesión y sus ejercicios en UNA sola transacción:
-- si algo falla, no se crea nada (ya no quedan sesiones sin ejercicios).
-- =====================================================================

create or replace function public.flexo_create_session(
  p_session jsonb,
  p_items   jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_id      uuid;
  v_n_items int  := 0;
begin
  if v_uid is null then
    raise exception 'Sesión no iniciada' using errcode = '28000';
  end if;
  if jsonb_typeof(p_session) is distinct from 'object' then
    raise exception 'Parámetros inválidos' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) is distinct from 'array' then
    raise exception 'p_items debe ser un arreglo' using errcode = '22023';
  end if;

  -- Solo campos conocidos; id, user_id, created_at y load se ignoran
  if exists (
    select 1 from jsonb_object_keys(p_session) as k
     where k not in ('goal_id', 'session_date', 'sport', 'duration_min', 'rpe',
                     'notes', 'planned_session_id', 'rest_seconds', 'route',
                     'id', 'user_id', 'created_at', 'load')
  ) then
    raise exception 'p_session contiene campos no permitidos' using errcode = '22023';
  end if;

  -- Si falta un campo obligatorio (fecha, deporte, duración, rpe), la columna
  -- NOT NULL hace fallar la función y no se crea nada.
  insert into public.flexo_sessions
    (user_id, goal_id, session_date, sport, duration_min, rpe, notes,
     planned_session_id, rest_seconds, route)
  values (
    v_uid,
    (p_session->>'goal_id')::uuid,
    (p_session->>'session_date')::date,
    p_session->>'sport',
    (p_session->>'duration_min')::int,
    (p_session->>'rpe')::int,
    p_session->>'notes',
    (p_session->>'planned_session_id')::uuid,
    coalesce((p_session->>'rest_seconds')::int, 0),
    nullif(p_session->'route', 'null'::jsonb)
  )
  returning id into v_id;

  insert into public.flexo_session_items (session_id, user_id, name, data)
  select v_id, v_uid, x.name, coalesce(x.data, '{}'::jsonb)
    from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb)) as x(name text, data jsonb);
  get diagnostics v_n_items = row_count;

  return jsonb_build_object('id', v_id, 'items', v_n_items);
end;
$$;

revoke all on function public.flexo_create_session(jsonb, jsonb) from public, anon;
grant execute on function public.flexo_create_session(jsonb, jsonb) to authenticated;
