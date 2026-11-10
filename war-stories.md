# Debugging War Stories — TNC Insurance Capstone
*For Hartford prep: simple English, STAR-shaped, with the numbers kept. Speak these — don't recite them.*

---

## War 1 — The Ghost Column (the big one)

**What we were trying to do**
Add a small feature: the admin "pending surveyor approvals" list should be **oldest-first** (fair FIFO). That needs a new column, `RegisteredAtUtc`, on the surveyor table — one entity property, one EF migration, one `orderby` line. A 15-minute change.

**What happened**
Everything broke at once:
- Registering a surveyor → **500 server error**
- Registering again → **409 "email already exists"**
- Surveyor login → **500**
- Admin pending-approvals page → **error**

**What we did, in order (and why)**
1. **Checked whether the migration was applied.** EF said `applied = True`. Looked done — but the errors continued. *Lesson seed: "applied" is a marker in a history table, not proof of schema.*
2. **Read `Program.cs`.** It calls `MigrateAsync()` at startup — so every restart self-heals pending migrations. That deepened the mystery: applied, yet broken.
3. **Suspected an orphaned row.** The first 500 left the login account created but the profile unsaved — that's why retrying said "email already exists" (409) instead of 500. Deleted the DB's sidecar files... but the main `.db` file stayed, so the orphan stayed. *Partial fix; real cause deeper.*
4. **Cut the system down to one moving part.** Skipped Angular and the gateway entirely — hit the service **directly via Swagger**. Still 500. So the bug lived *inside* AuthService. *Why: every layer you remove halves the suspects.*
5. **Read the server-side logs.** Our error middleware deliberately hides internals on 500s (that's correct for production), but logs the full stack. The log said: `SQLite Error 1: no such column: s.RegisteredAtUtc`. So the code asked for a column the database didn't have.
6. **The receipt that cracked it:** on a fresh DB rebuild, the startup log showed `Applying migration 'AddSurveyorRegisteredAtUtc'…` followed by **zero SQL** — straight to writing the history marker. The migration file's `Up()` method was **empty**. The column had never been created anywhere.
7. **Why it was empty:** EF scaffolds a migration as the *difference* between the last model snapshot and the current entities. The migration had been scaffolded before the entity change was compiled in — the diff was a photo of nothing. `dotnet ef migrations has-pending-model-changes` confirmed it in 2 seconds: "Changes have been made to the model — add a new migration."

**What worked**
Remove the hollow migration (`Remove-Migration`) → re-scaffold (`Add-Migration`) → **verify the new file actually contains `AddColumn<DateTime>` before running anything** → wipe dev DB → restart → `ALTER TABLE … ADD "RegisteredAtUtc"` appears in the log → register 200 → login 403 "pending approval" (the gate working) → admin 200 → approve → surveyor login 200.

**Lessons (say these out loud)**
- *"A green checkmark isn't a green schema."* Verify the artifact, not the status flag.
- *New workflow gate:* never run `database update`/restart without first opening the migration file and eyeballing the DDL.
- `dotnet ef migrations has-pending-model-changes` — the 2-second command that would have caught this on day one.
- Relative SQLite paths (`Data Source=TNC_Auth.db`) + multiple build outputs (`bin/…`) = silent "which database am I actually hitting?" drift.

---

## War 2 — The Test That Was Guarding a Bug

- **Goal:** one failing frontend spec out of 94; everything else green.
- **What happened:** the spec asserted that the company "My claims" filter sends `incidentFrom`/`incidentTo` query params.
- **The twist:** the **service had the bug** — the backend controller binds those filters as `from`/`to`. The spec had been written against the buggy behaviour, so the date filters had been **silently doing nothing** in production-shaped usage while tests stayed green.
- **Fix:** corrected the service to send `from`/`to` (and confirmed the surveyor queue genuinely wants `incidentFrom`/`incidentTo` — the two controllers *differ*), then updated the spec's two lines.
- **Lesson:** when a bugfix breaks a test, ask which side encoded reality. And brittle-but-important wiring (query-key names) deserves its own test — silent no-op filters are the worst kind of bug because nobody complains.

## War 3 — The Paste Gremlins

- **Goal:** move hardened code into the real repo via paste.
- **What happened:** build errors in `ClaimService.cs` that made no sense — comparisons missing their `==` operators. Chat had **eaten characters** during paste.
- **Fix:** restored the syntactically broken queries by comparing against the known-good pack version; adopted a rule: *never trust any pasted file verbatim — diff it against a baseline before building.*
- **Lesson:** transport layers (chat, CRLF line endings encoding uploads as "octet-stream") are part of the toolchain. Treat them as suspect as code.

## War 4 — The Phantom 41 (build-collapse theatre)

- **Goal:** restructure backend files (merge interfaces).
- **What happened:** **41 CS0006 "metadata file not found" errors** — looked catastrophic. Then, on a clean rebuild, **every single one vanished**. The survivors were three real but tiny errors (a stray `using` causing ambiguity, a duplicated `using`, two missing references).
- **Cause:** stale `bin/obj` build artifacts after moving files — the compiler was resolving ghosts of deleted files.
- **Lesson:** when the error count is absurdly high, **clean + rebuild before touching code**. Fix order matters: leaf projects first. Most "cascades" are one small error amplified.

## War 5 — The Impostor Health Check

- AuthService's `/health` endpoint proudly reported `"service": "QuoteService"` — a copy-paste fossil from project setup.
- Harmless to function, lethal to credibility in a demo ("so… which service is this, really?").
- **Lesson:** configs and boilerplate get **reviewed like code**. The interviewer reads JSON too.

## War 6 — The Rule That Ate Its Own Demo

- A self-imposed renewal rule (no renewal within 10 days) blocked the *happy-path demo* itself.
- **Fix:** removed for demo-friendliness, **flagged as an FR-silent deviation** in the design doc changelog rather than silently changed.
- **Lesson:** demo-script constraints can legitimately outrank self-imposed rules — but deviations are documented, never hidden. That's the same transparency discipline Hartford probes for with "what would you do differently?"

---

## The meta-method (this is the real answer to "walk me through your debugging approach")

1. **Reproduce at the narrowest layer** (Swagger direct > full UI).
2. **One change at a time, with a receipt each time** (a log line, a status code, a query result).
3. **Prefer the observation that *contradicts* your current theory** — the empty-DDL log line ended three theories at once.
4. **Write the fix down where Future-You will trip over it** (runbook + verification gate).

**30-second spoken version of War 1:**
> "A one-column EF migration turned into a full-stack outage — 500s on register and login, 409s on retry. The history table swore the migration had run, but reading the startup log showed it applied *with zero SQL* — the migration file was hollow because it had been scaffolded before the entity change was compiled. I bisected the system by calling the service directly, used server logs over the deliberately-generic 500 contract, confirmed with `has-pending-model-changes`, and re-scaffolded with a new gate: never apply a migration you haven't opened. Since then, every migration ships with its DDL eyeballed first."
