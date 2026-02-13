-- Task 1.2: Create shared data tables
-- Run in Supabase SQL editor (or as a migration).

create extension if not exists "pgcrypto";

create table if not exists public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.household_members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'editor', 'viewer')),
  created_at timestamptz not null default now(),
  unique (household_id, user_id)
);

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sku text,
  quantity numeric not null default 0,
  unit_value numeric,
  unit_type text,
  best_before date,
  location text,
  min_stock numeric not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  servings int,
  notes text,
  ingredients jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.meal_plan_entries (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid references public.recipes(id) on delete set null,
  scheduled_for date not null,
  servings int,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shopping_list_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  quantity numeric,
  unit_type text,
  checked boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Task 1.3: Add household_id to shared entities
--
-- Backfill strategy for existing rows:
-- 1) Add household_id as nullable.
-- 2) Backfill each row to a valid household.
--    - Option A: migrate each user's data into that user's household.
--    - Option B: create one temporary/default household and assign all legacy rows.
-- 3) Enforce NOT NULL after backfill and keep FK + index.

alter table public.inventory_items
  add column if not exists household_id uuid;

alter table public.recipes
  add column if not exists household_id uuid;

alter table public.meal_plan_entries
  add column if not exists household_id uuid;

alter table public.shopping_list_items
  add column if not exists household_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'inventory_items_household_id_fkey'
      and conrelid = 'public.inventory_items'::regclass
  ) then
    alter table public.inventory_items
      add constraint inventory_items_household_id_fkey
      foreign key (household_id) references public.households(id) on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'recipes_household_id_fkey'
      and conrelid = 'public.recipes'::regclass
  ) then
    alter table public.recipes
      add constraint recipes_household_id_fkey
      foreign key (household_id) references public.households(id) on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'meal_plan_entries_household_id_fkey'
      and conrelid = 'public.meal_plan_entries'::regclass
  ) then
    alter table public.meal_plan_entries
      add constraint meal_plan_entries_household_id_fkey
      foreign key (household_id) references public.households(id) on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'shopping_list_items_household_id_fkey'
      and conrelid = 'public.shopping_list_items'::regclass
  ) then
    alter table public.shopping_list_items
      add constraint shopping_list_items_household_id_fkey
      foreign key (household_id) references public.households(id) on delete cascade;
  end if;
end
$$;

create index if not exists inventory_items_household_id_idx
  on public.inventory_items (household_id);

create index if not exists recipes_household_id_idx
  on public.recipes (household_id);

create index if not exists meal_plan_entries_household_id_idx
  on public.meal_plan_entries (household_id);

create index if not exists shopping_list_items_household_id_idx
  on public.shopping_list_items (household_id);

-- Run after data backfill is complete.
-- alter table public.inventory_items alter column household_id set not null;
-- alter table public.recipes alter column household_id set not null;
-- alter table public.meal_plan_entries alter column household_id set not null;
-- alter table public.shopping_list_items alter column household_id set not null;

-- Task 1.4: Enforce household access policies (RLS)

-- Enable RLS
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.inventory_items enable row level security;
alter table public.recipes enable row level security;
alter table public.meal_plan_entries enable row level security;
alter table public.shopping_list_items enable row level security;

-- Utility predicates used by policies.
create or replace function public.is_household_member(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = auth.uid()
  );
$$;

create or replace function public.can_write_household(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = auth.uid()
      and hm.role in ('owner', 'editor')
  );
$$;

-- Household visibility and owner-only updates.
drop policy if exists households_select_member on public.households;
create policy households_select_member
  on public.households
  for select
  using (public.is_household_member(id));

drop policy if exists households_insert_owner on public.households;
create policy households_insert_owner
  on public.households
  for insert
  with check (auth.uid() is not null);

drop policy if exists households_update_owner on public.households;
create policy households_update_owner
  on public.households
  for update
  using (
    exists (
      select 1 from public.household_members hm
      where hm.household_id = id
        and hm.user_id = auth.uid()
        and hm.role = 'owner'
    )
  )
  with check (
    exists (
      select 1 from public.household_members hm
      where hm.household_id = id
        and hm.user_id = auth.uid()
        and hm.role = 'owner'
    )
  );

-- Membership rows: members can view, owners manage membership.
drop policy if exists household_members_select_member on public.household_members;
create policy household_members_select_member
  on public.household_members
  for select
  using (public.is_household_member(household_id));

drop policy if exists household_members_owner_insert on public.household_members;
create policy household_members_owner_insert
  on public.household_members
  for insert
  with check (
    exists (
      select 1 from public.household_members hm
      where hm.household_id = household_id
        and hm.user_id = auth.uid()
        and hm.role = 'owner'
    )
  );

drop policy if exists household_members_owner_update on public.household_members;
create policy household_members_owner_update
  on public.household_members
  for update
  using (
    exists (
      select 1 from public.household_members hm
      where hm.household_id = household_id
        and hm.user_id = auth.uid()
        and hm.role = 'owner'
    )
  )
  with check (
    exists (
      select 1 from public.household_members hm
      where hm.household_id = household_id
        and hm.user_id = auth.uid()
        and hm.role = 'owner'
    )
  );

drop policy if exists household_members_owner_delete on public.household_members;
create policy household_members_owner_delete
  on public.household_members
  for delete
  using (
    exists (
      select 1 from public.household_members hm
      where hm.household_id = household_id
        and hm.user_id = auth.uid()
        and hm.role = 'owner'
    )
  );

-- Shared entity policies. Members can read, owner/editor can write.
drop policy if exists inventory_items_select_member on public.inventory_items;
create policy inventory_items_select_member
  on public.inventory_items
  for select
  using (public.is_household_member(household_id));

drop policy if exists inventory_items_insert_writer on public.inventory_items;
create policy inventory_items_insert_writer
  on public.inventory_items
  for insert
  with check (public.can_write_household(household_id));

drop policy if exists inventory_items_update_writer on public.inventory_items;
create policy inventory_items_update_writer
  on public.inventory_items
  for update
  using (public.can_write_household(household_id))
  with check (public.can_write_household(household_id));

drop policy if exists inventory_items_delete_writer on public.inventory_items;
create policy inventory_items_delete_writer
  on public.inventory_items
  for delete
  using (public.can_write_household(household_id));

drop policy if exists recipes_select_member on public.recipes;
create policy recipes_select_member
  on public.recipes
  for select
  using (public.is_household_member(household_id));

drop policy if exists recipes_insert_writer on public.recipes;
create policy recipes_insert_writer
  on public.recipes
  for insert
  with check (public.can_write_household(household_id));

drop policy if exists recipes_update_writer on public.recipes;
create policy recipes_update_writer
  on public.recipes
  for update
  using (public.can_write_household(household_id))
  with check (public.can_write_household(household_id));

drop policy if exists recipes_delete_writer on public.recipes;
create policy recipes_delete_writer
  on public.recipes
  for delete
  using (public.can_write_household(household_id));

drop policy if exists meal_plan_entries_select_member on public.meal_plan_entries;
create policy meal_plan_entries_select_member
  on public.meal_plan_entries
  for select
  using (public.is_household_member(household_id));

drop policy if exists meal_plan_entries_insert_writer on public.meal_plan_entries;
create policy meal_plan_entries_insert_writer
  on public.meal_plan_entries
  for insert
  with check (public.can_write_household(household_id));

drop policy if exists meal_plan_entries_update_writer on public.meal_plan_entries;
create policy meal_plan_entries_update_writer
  on public.meal_plan_entries
  for update
  using (public.can_write_household(household_id))
  with check (public.can_write_household(household_id));

drop policy if exists meal_plan_entries_delete_writer on public.meal_plan_entries;
create policy meal_plan_entries_delete_writer
  on public.meal_plan_entries
  for delete
  using (public.can_write_household(household_id));

drop policy if exists shopping_list_items_select_member on public.shopping_list_items;
create policy shopping_list_items_select_member
  on public.shopping_list_items
  for select
  using (public.is_household_member(household_id));

drop policy if exists shopping_list_items_insert_writer on public.shopping_list_items;
create policy shopping_list_items_insert_writer
  on public.shopping_list_items
  for insert
  with check (public.can_write_household(household_id));

drop policy if exists shopping_list_items_update_writer on public.shopping_list_items;
create policy shopping_list_items_update_writer
  on public.shopping_list_items
  for update
  using (public.can_write_household(household_id))
  with check (public.can_write_household(household_id));

drop policy if exists shopping_list_items_delete_writer on public.shopping_list_items;
create policy shopping_list_items_delete_writer
  on public.shopping_list_items
  for delete
  using (public.can_write_household(household_id));

-- Manual validation checklist for access controls:
-- 1) As owner/editor of household A, verify CRUD succeeds in household A.
-- 2) As viewer of household A, verify SELECT succeeds and write statements fail.
-- 3) As member of household B only, verify household A rows are invisible.
