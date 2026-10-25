-- =====================================================================
-- FLEXO · Migraciones aplicadas en Supabase (copia para el repositorio)
-- Proyecto: glomtdofnkayvwslxqko
-- =====================================================================

-- ---------------------------------------------------------------------
-- Migración 1: flexo_update_session_columnas_explicitas
-- Edita una sesión y reemplaza sus ejercicios en UNA sola transacción.
-- Si algo falla, todo se revierte.
-- ---------------------------------------------------------------------
create or replace function public.flexo_update_session(
  p_session_id text,
  p_session    jsonb,
  p_items      jsonb default '[]'::jsonb
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
  if p_session_id is null or jsonb_typeof(p_session) is distinct from 'object' then
    raise exception 'Parámetros inválidos' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) is distinct from 'array' then
    raise exception 'p_items debe ser un arreglo' using errcode = '22023';
  end if;

  begin
    v_id := p_session_id::uuid;
  exception when invalid_text_representation then
    raise exception 'Id de sesión inválido' using errcode = '22023';
  end;

  -- Solo se aceptan campos conocidos de flexo_sessions.
  -- id, user_id, created_at y load (columna generada) se ignoran.
  if exists (
    select 1 from jsonb_object_keys(p_session) as k
     where k not in ('goal_id', 'session_date', 'sport', 'duration_min', 'rpe',
                     'notes', 'planned_session_id', 'rest_seconds', 'route',
                     'id', 'user_id', 'created_at', 'load')
  ) then
    raise exception 'p_session contiene campos no permitidos' using errcode = '22023';
  end if;

  -- Bloquea la fila (serializa guardados simultáneos como el doble clic)
  perform 1 from public.flexo_sessions where id = v_id and user_id = v_uid for update;
  if not found then
    raise exception 'Sesión no encontrada o sin permiso' using errcode = 'P0002';
  end if;

  -- Actualiza solo los campos que llegan en p_session
  update public.flexo_sessions s set
    goal_id            = case when p_session ? 'goal_id'            then (p_session->>'goal_id')::uuid            else s.goal_id end,
    session_date       = case when p_session ? 'session_date'       then (p_session->>'session_date')::date       else s.session_date end,
    sport              = case when p_session ? 'sport'              then p_session->>'sport'                      else s.sport end,
    duration_min       = case when p_session ? 'duration_min'       then (p_session->>'duration_min')::int        else s.duration_min end,
    rpe                = case when p_session ? 'rpe'                then (p_session->>'rpe')::int                 else s.rpe end,
    notes              = case when p_session ? 'notes'              then p_session->>'notes'                      else s.notes end,
    planned_session_id = case when p_session ? 'planned_session_id' then (p_session->>'planned_session_id')::uuid else s.planned_session_id end,
    rest_seconds       = case when p_session ? 'rest_seconds'       then (p_session->>'rest_seconds')::int        else s.rest_seconds end,
    route              = case when p_session ? 'route'              then nullif(p_session->'route', 'null'::jsonb) else s.route end
  where s.id = v_id and s.user_id = v_uid;

  -- Reemplaza los ejercicios
  delete from public.flexo_session_items where session_id = v_id and user_id = v_uid;

  insert into public.flexo_session_items (session_id, user_id, name, data)
  select v_id, v_uid, x.name, coalesce(x.data, '{}'::jsonb)
    from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb)) as x(name text, data jsonb);
  get diagnostics v_n_items = row_count;

  return jsonb_build_object('id', v_id, 'items', v_n_items);
end;
$$;

revoke all on function public.flexo_update_session(text, jsonb, jsonb) from public, anon;
grant execute on function public.flexo_update_session(text, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- Migración 2: flexo_politicas_solo_authenticated
-- Las políticas own_* pasan de {public} a {authenticated}.
-- La condición (user_id = auth.uid()) no cambia.
-- ---------------------------------------------------------------------
alter policy own_flexo_daily_status     on public.flexo_daily_status     to authenticated;
alter policy own_goals                  on public.flexo_goals            to authenticated;
alter policy own_flexo_plan_blocks      on public.flexo_plan_blocks      to authenticated;
alter policy own_flexo_planned_sessions on public.flexo_planned_sessions to authenticated;
alter policy own_profiles               on public.flexo_profiles         to authenticated;
alter policy own_items                  on public.flexo_session_items    to authenticated;
alter policy own_sessions               on public.flexo_sessions         to authenticated;
alter policy own_flexo_tests            on public.flexo_tests            to authenticated;
