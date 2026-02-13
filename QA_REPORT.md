# QA Test Report

## Scope
- Repository inspected: single-page `index.html` inventory app.
- Attempted runtime UI automation through Playwright browser container against a local HTTP server.
- Performed source-level behavioral review for all major flows: auth, inventory CRUD, import/export, recipes, meal planning, shopping list, barcode/date scanning.

## Test execution notes
1. Started local server with `python3 -m http.server 4173 --bind 0.0.0.0`.
2. Attempted end-to-end browser automation using the provided browser tool.
3. Browser container was unstable (timeouts / browser crash), so full interactive regression could not be completed in this environment.

## Unexpected or non-logical behaviors found

1. **“Meal planning” dates do not influence shopping list generation.**
   - `mealPlan.start` and `mealPlan.days` are collected and saved, but `buildShoppingList()` iterates all plan entries without filtering by date window.
   - User-visible effect: changing planning period appears meaningful in UI, but it does not affect the generated shopping list logic.

2. **Only one account is supported despite username-based auth UI.**
   - Signup blocks creating a second account if any auth record already exists.
   - User-visible effect: the app asks for usernames but behaves like single-account local app, which can be surprising.

3. **Shopping list matching is purely by ingredient/item name string.**
   - Availability map keys by `item.name`, required map keys by `ingredient.name`; SKU is ignored.
   - User-visible effect: `Tomato` vs `Tomatoes` (or minor naming differences) are treated as unrelated, resulting in unexpected “missing” items.

4. **Import success count can be misleading when rows merge into existing SKUs.**
   - Import reports `Imported N item(s)` even when many records are merged/updated rather than inserted as new rows.
   - User-visible effect: message implies all were new imports, not a mix of inserts and updates.

5. **Ambiguous scanned date parsing may produce unexpected month/day interpretation.**
   - For scanned `d/m/y` or `m/d/y`, parser uses a heuristic (`first > 12`) and defaults otherwise.
   - User-visible effect: dates like `10/11/24` are ambiguous and may be interpreted differently than user intent.

## Overall
The codebase is structurally coherent, but the above points are likely to feel inconsistent or confusing to users and should be clarified in UX copy or corrected in logic.
