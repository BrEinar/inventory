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

-- Bootstrap helper: ensure signed-in user always has a household they own.
-- Uses SECURITY DEFINER so initial owner membership can be created without
-- requiring an existing owner row.
create or replace function public.ensure_household_for_current_user()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_household uuid;
  new_household uuid;
begin
  select hm.household_id into existing_household
  from public.household_members hm
  where hm.user_id = auth.uid()
  order by hm.created_at asc
  limit 1;

  if existing_household is not null then
    return existing_household;
  end if;

  insert into public.households(name)
  values ('My household')
  returning id into new_household;

  insert into public.household_members(household_id, user_id, role)
  values (new_household, auth.uid(), 'owner');

  return new_household;
end;
$$;

grant execute on function public.ensure_household_for_current_user() to authenticated;

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

-- Phase 2.3 / 2.4 and Phase 3 additions

-- Activity metadata
alter table public.inventory_items add column if not exists updated_by uuid references auth.users(id);
alter table public.recipes add column if not exists updated_by uuid references auth.users(id);

-- Keep updated_at fresh automatically.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists inventory_items_touch_updated_at on public.inventory_items;
create trigger inventory_items_touch_updated_at
before update on public.inventory_items
for each row execute function public.touch_updated_at();

drop trigger if exists recipes_touch_updated_at on public.recipes;
create trigger recipes_touch_updated_at
before update on public.recipes
for each row execute function public.touch_updated_at();

-- Invite flow
create table if not exists public.household_invites (
  code text primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_by uuid references auth.users(id),
  used_at timestamptz
);

alter table public.household_invites enable row level security;

drop policy if exists household_invites_select_member on public.household_invites;
create policy household_invites_select_member
  on public.household_invites
  for select
  using (public.is_household_member(household_id));

-- create invite code (owner only)
create or replace function public.create_household_invite(target_household_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  out_code text;
begin
  if not exists (
    select 1 from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = auth.uid()
      and hm.role = 'owner'
  ) then
    raise exception 'Only owner can create invites';
  end if;

  out_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  insert into public.household_invites(code, household_id, created_by)
  values (out_code, target_household_id, auth.uid());
  return out_code;
end;
$$;

grant execute on function public.create_household_invite(uuid) to authenticated;

-- accept invite code and join household as editor
create or replace function public.accept_household_invite(invite_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_household uuid;
begin
  select household_id into target_household
  from public.household_invites hi
  where hi.code = upper(trim(invite_code))
    and hi.used_at is null
    and hi.expires_at > now();

  if target_household is null then
    raise exception 'Invite code is invalid or expired';
  end if;

  insert into public.household_members(household_id, user_id, role)
  values (target_household, auth.uid(), 'editor')
  on conflict (household_id, user_id) do nothing;

  update public.household_invites
  set used_by = auth.uid(), used_at = now()
  where code = upper(trim(invite_code));
end;
$$;

grant execute on function public.accept_household_invite(text) to authenticated;

-- Conflict-safe quantity update
create or replace function public.adjust_inventory_qty(target_item_id uuid, target_household_id uuid, qty_delta numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_write_household(target_household_id) then
    raise exception 'No write access for household';
  end if;

  update public.inventory_items
  set quantity = greatest(0, quantity + qty_delta),
      updated_by = auth.uid(),
      updated_at = now()
  where id = target_item_id
    and household_id = target_household_id;

  if not found then
    raise exception 'Item not found';
  end if;
end;
$$;

grant execute on function public.adjust_inventory_qty(uuid, uuid, numeric) to authenticated;
