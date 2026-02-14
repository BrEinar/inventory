# Inventory App

A single-page inventory app for households.

## What the app does

- Track inventory items with quantity, unit, location, notes, and per-item best-before dates.
- Scan barcodes with the camera.
- Create recipes.
- Build a meal plan.
- Generate a shopping list from planned meals.
- Import/export data as JSON or CSV.
- Sync inventory data through Supabase cloud storage.

---

## Quick start

This repo is currently a static app (`index.html`).

### 1) Configure built-in cloud credentials (one-time app setup)

Set your Supabase URL and anon key in `index.html`:

```js
const BUILT_IN_SUPABASE_CONFIG = Object.freeze({
  url: "https://YOUR_PROJECT_REF.supabase.co",
  anonKey: "YOUR_SUPABASE_ANON_KEY",
});
```

This is done once by the app owner. End users do not need browser console setup.

### 2) Apply database SQL

- Open Supabase SQL Editor.
- Run `supabase_phase1_task1_2_tables.sql` from this repo.

This creates the household/data tables, RLS policies, and required RPC functions used by the app.

### 3) Run the app

Option A: open `index.html` directly in a modern browser.

Option B (recommended):

```bash
python3 -m http.server 8080
```

Then open: `http://localhost:8080`

---

## User onboarding (cloud only)

1. Sign up with **email + password**.
2. Log in.
3. Use **Create invite code** / **Join household** to share a household.

All app data is cloud-backed and shared by household.

---

## Notes

- The app keeps a local cache for resilience, but source-of-truth data is cloud state.
- If `BUILT_IN_SUPABASE_CONFIG` is not set, login/signup is disabled and the app shows a configuration error.
