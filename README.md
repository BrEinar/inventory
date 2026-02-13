# Inventory App

A single-page inventory app for households.

## What the app does

- Track inventory items with quantity, unit, location, notes, and per-item best-before dates.
- Scan barcodes with the camera.
- Create recipes.
- Build a meal plan.
- Generate a shopping list from planned meals.
- Import/export data as JSON or CSV.

The app supports two storage modes:

1. **Local mode (default)**
   - Data is stored in browser `localStorage` on that device.
   - Local accounts are device-only.
   - Good for one-device use.

2. **Cloud mode (Supabase)**
   - Uses Supabase Auth + Postgres tables.
   - Supports household sharing across devices.
   - Uses invite codes to add members to the same household.

---

## Quick start

This repo is currently a static app (`index.html`).

### Option A: open directly

- Open `index.html` in a modern browser.

### Option B: serve locally (recommended)

```bash
python3 -m http.server 8080
```

Then open: `http://localhost:8080`

---

## Using the app on one device (no cloud)

1. Open the app.
2. Sign up with a username + password.
3. Log in and start adding items.

In this mode, data remains on that browser/device.

---

## Multi-device household setup (shared data)

To share data between phones/computers, you must configure Supabase.

### 1) Create a Supabase project

- Create a project in Supabase.
- Get:
  - Project URL
  - Project anon key

### 2) Apply database SQL

- Open Supabase SQL Editor.
- Run `supabase_phase1_task1_2_tables.sql` from this repo.

This creates the household/data tables, RLS policies, and required RPC functions used by the app.

### 3) Configure the app with your Supabase credentials

Currently there is no in-app settings screen for this. Set config in browser console:

```js
localStorage.setItem(
  "inventory_supabase_config_v1",
  JSON.stringify({
    url: "https://YOUR_PROJECT_REF.supabase.co",
    anonKey: "YOUR_SUPABASE_ANON_KEY"
  })
);
location.reload();
```

After reload, login text should indicate cloud auth is enabled.

### 4) Create cloud accounts on each device

- Use **email + password** signup/login in the app on each device.
- Each household member should use their own account.

### 5) Put everyone in the same household

1. On one logged-in device, click **Create invite code**.
2. Share the code with another household member.
3. On the other device, paste code and click **Join household**.

Once in the same household, inventory/recipes/meal-plan/shopping-list data sync by `household_id`.

---

## Notes

- Without Supabase config, sharing between devices is not available.
- Cloud mode still keeps a local cache for resilience.
- If you want to reset cloud mode on a device, remove `inventory_supabase_config_v1` from localStorage and reload.

