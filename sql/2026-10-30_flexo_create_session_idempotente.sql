-- =====================================================================
-- FLEXO · Migración aplicada en Supabase: flexo_create_session_idempotente
-- Proyecto: glomtdofnkayvwslxqko
-- Crear una sesión de forma idempotente: el cliente puede enviar su propio id
-- (p_session->>'id'). Si la sesión con ese id ya existe y es del mismo usuario, no se
-- duplica (reintento tras un corte de red). Sin id, se genera uno (comportamiento anterior).
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
  v_new     uuid;
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

  -- Solo campos conocidos; user_id, created_at y load se ignoran
  if exists (
    select 1 from jsonb_object_keys(p_session) as k
     where k not in ('goal_id', 'session_date', 'sport', 'duration_min', 'rpe',
                     'notes', 'planned_session_id', 'rest_seconds', 'route',
                     'id', 'user_id', 'created_at', 'load')
  ) then
    raise exception 'p_session contiene campos no permitidos' using errcode = '22023';
  end if;

  -- Id elegido por el cliente (opcional) o generado aquí
  if nullif(p_session->>'id', '') is not null then
    begin
      v_id := (p_session->>'id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Id de sesión inválido' using errcode = '22023';
    end;
  else
    v_id := gen_random_uuid();
  end if;

  -- Si falta un campo obligatorio (fecha, deporte, duración, rpe), la columna
  -- NOT NULL hace fallar la función y no se crea nada.
  insert into public.flexo_sessions
    (id, user_id, goal_id, session_date, sport, duration_min, rpe, notes,
     planned_session_id, rest_seconds, route)
  values (
    v_id,
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
  on conflict (id) do nothing
  returning id into v_new;

  if v_new is null then
    -- Ya existía: es un reintento solo si la sesión es del mismo usuario
    if exists (select 1 from public.flexo_sessions where id = v_id and user_id = v_uid) then
      select count(*) into v_n_items from public.flexo_session_items where session_id = v_id;
      return jsonb_build_object('id', v_id, 'items', v_n_items, 'duplicate', true);
    end if;
    raise exception 'Id de sesión en uso' using errcode = '23505';
  end if;

  insert into public.flexo_session_items (session_id, user_id, name, data)
  select v_id, v_uid, x.name, coalesce(x.data, '{}'::jsonb)
    from jsonb_to_recordset(coalesce(p_items, '[]'::jsonb)) as x(name text, data jsonb);
  get diagnostics v_n_items = row_count;

  return jsonb_build_object('id', v_id, 'items', v_n_items, 'duplicate', false);
end;
$$;

revoke all on function public.flexo_create_session(jsonb, jsonb) from public, anon;
grant execute on function public.flexo_create_session(jsonb, jsonb) to authenticated;
