# Shared Multi-Device Inventory: What to Choose for Your Household

You asked what to choose to get this working for a real household with multiple people and devices.

## Short answer (recommended)
Choose **Managed Backend** (Supabase is a strong default) and implement shared `household` workspaces with role-based membership.

Why:
- Fastest path to working multi-user, multi-device sync.
- Lowest early cost and lowest operational burden.
- Easy to evolve later if you outgrow it.

---

## Cost differences (practical ranges)

### Option A — Managed backend (Supabase/Firebase/Appwrite)
**Best for you right now.**

- MVP (~up to 100 households): **$0–$25/month**
- Growth (~1k households): **$25–$150/month**
- Larger (~10k households): **$150–$800+/month**

Engineering effort:
- Initial build: **2–6 weeks** (single dev)
- Ongoing maintenance: **low–medium**

### Option B — Custom backend (your own API + Postgres)

- MVP: **$20–$120/month**
- Growth: **$100–$500/month**
- Larger: **$500–$2,000+/month**

Engineering effort:
- Initial build: **4–12+ weeks**
- Ongoing maintenance: **medium–high**

### Option C — Local-first sync engine

- Backend bill: similar to A/B, often **+10–40%** overhead
- Highest engineering complexity by far

Engineering effort:
- Initial build: **8–20+ weeks**
- Ongoing maintenance: **high**

---

## Decision table

- Want this live quickly with low risk/cost? → **Option A**
- Need deep custom/compliance/control from day 1? → **Option B**
- Need best offline/conflict behavior and can invest heavily? → **Option C**

For a household inventory/meal-planning app, **Option A is the right starting point**.

---

## “Get this done” implementation plan (Option A)

### Phase 1 (Week 1): shared account model
1. Add cloud auth (email+password).
2. Create tables:
   - `households`
   - `household_members` (`owner`, `editor`, `viewer`)
   - `inventory_items`
   - `recipes`
   - `meal_plan_entries`
   - `shopping_list_items`
3. Add `household_id` to every shared table.
4. Add access policies: user can read/write only households they belong to.

### Phase 2 (Week 2): sync app screens
1. Replace local-only reads/writes with cloud reads/writes.
2. Keep local cache for better UX.
3. Enable realtime only for:
   - inventory quantity updates
   - shopping list edits
4. Add invite flow (owner invites family members).

### Phase 3 (Week 3): household-ready polish
1. Add activity log (`updated_by`, `updated_at`) on key entities.
2. Add conflict-safe updates for quantities.
3. Add backup/export and account recovery UX.

## Implementation task checklist

Use this as a working task board. Each task maps directly to the plan points above.

### Phase 1 (Week 1): shared account model

- [x] **Task 1.1 — Add cloud auth (email+password).**
  - [x] Choose provider config (project URL, anon/public key, auth settings).
  - [x] Implement sign up, sign in, sign out flows.
  - [x] Persist and restore authenticated session on app load.
  - [x] Add basic auth error handling and user-facing messages.

- [x] **Task 1.2 — Create shared data tables.**
  - [x] Create `households` table.
  - [x] Create `household_members` table with roles: `owner`, `editor`, `viewer`.
  - [x] Create `inventory_items` table.
  - [x] Create `recipes` table.
  - [x] Create `meal_plan_entries` table.
  - [x] Create `shopping_list_items` table.

- [ ] **Task 1.3 — Add `household_id` to shared entities.**
  - [ ] Ensure every shared table includes `household_id`.
  - [ ] Add foreign keys and indexes for `household_id`.
  - [ ] Backfill/default `household_id` strategy for existing data.

- [ ] **Task 1.4 — Enforce household access policies.**
  - [ ] Enable row-level security (or equivalent).
  - [ ] Add read/write policies scoped to household membership.
  - [ ] Validate role constraints (`owner`, `editor`, `viewer`) for write operations.
  - [ ] Test unauthorized cross-household access is blocked.

### Phase 2 (Week 2): sync app screens

- [ ] **Task 2.1 — Replace local-only reads/writes with cloud reads/writes.**
  - [ ] Migrate inventory CRUD operations to backend APIs.
  - [ ] Migrate recipe CRUD operations to backend APIs.
  - [ ] Migrate meal plan CRUD operations to backend APIs.
  - [ ] Migrate shopping list CRUD operations to backend APIs.

- [ ] **Task 2.2 — Keep local cache for better UX.**
  - [ ] Add cache layer keyed by `household_id`.
  - [ ] Hydrate UI from cache first, then revalidate in background.
  - [ ] Define cache invalidation strategy after mutations/realtime events.

- [ ] **Task 2.3 — Enable realtime only for high-value updates.**
  - [ ] Enable realtime for inventory quantity updates.
  - [ ] Enable realtime for shopping list edits.
  - [ ] Keep other entities on fetch/refresh to limit noise/cost.
  - [ ] Verify multi-device updates appear promptly.

- [ ] **Task 2.4 — Add invite flow for family members.**
  - [ ] Add owner-only “invite member” UI.
  - [ ] Generate/send invite links or codes.
  - [ ] Implement invite acceptance and membership creation.
  - [ ] Add member management view (role updates/removal).

### Phase 3 (Week 3): household-ready polish

- [ ] **Task 3.1 — Add activity metadata on key entities.**
  - [ ] Add `updated_by` and `updated_at` fields where needed.
  - [ ] Auto-populate metadata in write paths.
  - [ ] Surface recent updates in UI where helpful.

- [ ] **Task 3.2 — Add conflict-safe quantity updates.**
  - [ ] Use atomic increment/decrement operations server-side.
  - [ ] Add optimistic UI with rollback on conflict/failure.
  - [ ] Test concurrent edits from two devices.

- [ ] **Task 3.3 — Add backup/export and account recovery UX.**
  - [ ] Provide household data export (CSV/JSON).
  - [ ] Add import/restore path with validation.
  - [ ] Add password reset/account recovery flow.
  - [ ] Add user guidance for recovery and data safety.

---

## First 6-month budget expectation

- **Managed backend path:** generally lowest total cost to launch and operate early.
- **Custom backend path:** can cost more in engineering time even if infra seems similar.
- **Local-first sync path:** highest engineering cost and QA complexity.

---

## Final recommendation
If the goal is: “my household can all use and edit the same data from different devices soon,”
start with **Managed Backend (Option A)** now.
