-- FLEXO · schema completo (v1.2 a v1.8) en un solo script
-- Ejecutar UNA vez en Supabase > SQL Editor. Es seguro volver a correrlo: no borra datos.
-- No toca las tablas anteriores (workouts, workout_sets) ni la tabla profiles de Supabase.

-- ======================== Tablas base: perfil, metas, sesiones y series ========================

create table if not exists flexo_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  sports jsonb not null default '[]',      -- [{"sport":"running","level":"intermedio"}]
  days int[] not null default '{}',        -- 1=lunes ... 7=domingo
  equipment text,
  limitations text,                        -- opcional, dato sensible
  updated_at timestamptz not null default now()
);

create table if not exists flexo_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  sport text not null,
  metric text not null,                    -- "Tiempo en 10 km"
  unit text not null,                      -- "min", "kg"
  base_value numeric not null,             -- dónde estás hoy
  target_value numeric not null,
  current_value numeric not null,
  higher_is_better boolean not null,
  due_date date not null,
  status text not null default 'activa' check (status in ('activa','lograda','archivada')),
  created_at timestamptz not null default now(),
  check (target_value <> base_value)
);

create table if not exists flexo_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  goal_id uuid references flexo_goals(id) on delete set null,
  session_date date not null,
  sport text not null,
  duration_min int not null check (duration_min > 0),
  rpe int not null check (rpe between 1 and 10),
  load int generated always as (duration_min * rpe) stored,
  notes text,
  planned_session_id uuid,                 -- reservado para la Fase 3
  created_at timestamptz not null default now()
);

create table if not exists flexo_session_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references flexo_sessions(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,                      -- ejercicio o segmento
  data jsonb not null default '{}'         -- campos variables según la plantilla del deporte
);

create index if not exists flexo_sessions_user_date on flexo_sessions(user_id, session_date desc);
create index if not exists flexo_items_session on flexo_session_items(session_id);

alter table flexo_profiles enable row level security;
alter table flexo_goals enable row level security;
alter table flexo_sessions enable row level security;
alter table flexo_session_items enable row level security;

drop policy if exists own_profiles on flexo_profiles;
create policy own_profiles on flexo_profiles for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists own_goals on flexo_goals;
create policy own_goals on flexo_goals for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists own_sessions on flexo_sessions;
create policy own_sessions on flexo_sessions for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists own_items on flexo_session_items;
create policy own_items on flexo_session_items for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ======================== Descanso total de la sesión ========================
alter table flexo_sessions add column if not exists rest_seconds int not null default 0;

-- ======================== Plan semanal ========================

create table if not exists flexo_plan_blocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  goal_id uuid not null references flexo_goals(id) on delete cascade,
  name text not null,
  start_date date not null,
  end_date date not null,
  position int not null default 0,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table if not exists flexo_planned_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  goal_id uuid not null references flexo_goals(id) on delete cascade,
  block_id uuid references flexo_plan_blocks(id) on delete set null,
  planned_date date not null,
  sport text not null,
  duration_min int not null check (duration_min > 0),
  notes text,
  created_at timestamptz not null default now()
);

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'flexo_sessions_planned_fk') then
    alter table flexo_sessions add constraint flexo_sessions_planned_fk
      foreign key (planned_session_id) references flexo_planned_sessions(id) on delete set null;
  end if;
end $$;

create index if not exists flexo_blocks_goal on flexo_plan_blocks(goal_id);
create index if not exists flexo_planned_goal_date on flexo_planned_sessions(goal_id, planned_date);

alter table flexo_plan_blocks enable row level security;
alter table flexo_planned_sessions enable row level security;
drop policy if exists own_flexo_plan_blocks on flexo_plan_blocks;
create policy own_flexo_plan_blocks on flexo_plan_blocks for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists own_flexo_planned_sessions on flexo_planned_sessions;
create policy own_flexo_planned_sessions on flexo_planned_sessions for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ======================== Estado diario ========================

create table if not exists flexo_daily_status (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  status_date date not null,
  sleep_hours numeric check (sleep_hours >= 0 and sleep_hours <= 24),
  fatigue int check (fatigue between 1 and 5),   -- 1 = muy descansado, 5 = muy cansado
  pain int check (pain between 0 and 5),         -- 0 = ninguno, 5 = muy fuerte
  mood int check (mood between 1 and 5),         -- 1 = bajo, 5 = muy bueno
  notes text,
  created_at timestamptz not null default now(),
  unique (user_id, status_date),
  check (sleep_hours is not null or fatigue is not null or pain is not null or mood is not null)
);

create index if not exists flexo_daily_user_date on flexo_daily_status(user_id, status_date desc);

alter table flexo_daily_status enable row level security;
drop policy if exists own_flexo_daily_status on flexo_daily_status;
create policy own_flexo_daily_status on flexo_daily_status for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ======================== Pruebas de referencia ========================

create table if not exists flexo_tests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  goal_id uuid not null references flexo_goals(id) on delete cascade,
  test_date date not null,
  value numeric not null,          -- resultado en la unidad de la meta (min, kg, repeticiones, seg, km)
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists flexo_tests_goal_date on flexo_tests(goal_id, test_date);

alter table flexo_tests enable row level security;
drop policy if exists own_flexo_tests on flexo_tests;
create policy own_flexo_tests on flexo_tests for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ======================== Ruta GPS de la sesión ========================

alter table flexo_sessions add column if not exists route jsonb;  -- [[lat, lng], ...] simplificada

-- ======================== Preferencias de la cuenta (alertas vistas, opciones de compartir) ========================
alter table flexo_profiles add column if not exists prefs jsonb not null default '{}';
