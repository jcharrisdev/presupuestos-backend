## Brief

### TLDR
Add a minimal automated safety net for Salarying's backend: unit tests for the existing pure
money-calculation functions in `backend/server.js` (quincenas, deudas, estado anual), plus a
GitHub Actions workflow that runs them on every push to `main`. No refactor, no new runtime
dependencies, nothing blocks the existing manual deploy process.

### Goal
Catch a class of bug — wrong money math in quincenas/deudas/estado-anual — before it reaches
production, given the app has zero automated tests today and several recent `fix(ia)` commits
re-fixed the same pagos/quincenas logic.

### Constraints
- No new npm dependencies (backend `package.json` has none today) — use Node's built-in
  `node:test` + `assert`.
- No changes to route/DB logic in `server.js` beyond adding one `module.exports = { ... }` block
  at the end of the file, listing only the already-DB-free pure functions under test.
- Does not touch the existing deploy flow (`flutter build web` → commit+push → curl to Render).
  CI is purely informational (pass/fail on the commit); it does not gate or trigger the deploy.
- Flutter/Dart tests are explicitly out of scope for this pass (see Out-of-scope).

### Acceptance criteria
- The 7 target pure functions (`_montoMensual`, `_generarAplicaMeses`, `calcularFechaFin`,
  `_simularDeudas`, `_construirTimeline`, `calcularSplits`, `_calcularScore`) are testable in
  isolation without executing any of `server.js`'s side effects.
- A `backend/test/` (or similar) directory has `node:test` unit tests covering each exported
  function above with at least one normal case and one edge case (e.g. `_simularDeudas` with
  both `avalanche` and `snowball` strategies; `calcularFechaFin` across month boundaries).
- `backend/package.json` `"test"` script actually runs the new tests (replacing today's
  `"echo ... && exit 1"` stub) and exits 0 when they pass.
- A `.github/workflows/backend-tests.yml` workflow runs `npm test` inside `backend/` on every
  push to `main`, and its pass/fail is visible on the commit/PR checks.
- Running the new tests locally and in CI both pass against the current `main`.

### Captured assumptions
- Q1 — which functions to test first: the pure calculation functions tied to the recurring
  pagos/quincenas/deudas bug area, not invoice-parsing or other less-critical pure functions.
- Q2 — exposure mechanism: originally planned as a single added `module.exports` block with no
  extraction. Revised mid-implementation once a fact-check showed `server.js` has real
  module-load side effects (`mysql.createPool(...)` at load time, `cron.schedule(...)` x2,
  `app.listen(...)`) that would fire the moment any test file did `require('../server.js')` —
  including attempting to connect to the real Clever Cloud MySQL DB in CI. Resolved by moving the
  7 pure functions verbatim (no logic changes) into a new zero-dependency
  `backend/lib/calculos_financieros.js`, required by both `server.js` (for the routes that used
  them) and the new tests. Still not the "split server.js" candidate — that one is untouched.
- Q3 — test framework: Node's built-in `node:test`, not Jest, to add zero dependencies.
- Q4 — CI scope: backend only for this pass; Flutter CI (even just `flutter analyze`) deferred
  until there's a real Flutter test worth gating.
- Q5 — gate strictness: informational only (workflow runs and shows a check on the commit); not
  wired to block or trigger the Render deploy.
All five resolved by autonomous agent decision per the user's explicit request (2026-09-17) to
work autonomously and avoid technical back-and-forth — the user is Salarying's non-technical
idea-owner, not its coder, and asked not to be interviewed on implementation-level forks. See
project memory `feedback-autonomous-mode-salarying`.

### Out-of-scope
- Any Flutter/Dart automated tests (frontend has only the default placeholder test today).
- Splitting/refactoring `backend/server.js` itself (separate, not-yet-picked improvement
  candidate — this Brief only adds an export block, no logic changes).
- Wiring CI to gate or trigger the Render deploy.
- Testing route handlers / DB-touching code paths (would need DB mocking or a test DB — larger
  effort than this "minimal safety net" pass).

### Deferred questions
None — all open forks were product-neutral implementation decisions, resolved autonomously per
the user's standing instruction (see Captured assumptions).
