# TNC Insurance — v3.2 Smoke Test Runbook (7 checks)

**When:** after rebase paste + migrations, with the full stack running.
**Stack:** frontend `localhost:4200` → gateway `:5000` → Auth `:5280`, Quote `:5123`, Insurance `:5196`, Customer `:5179` (if a port differs on your machine, check that service's `Properties/launchSettings.json`).
**Where to test:** claim-filing negative tests are best done in **InsuranceService Swagger** (`http://localhost:5196/swagger`) because the UI date-pickers *correctly* discourage future dates ("hints, not enforcement") — the authoritative checks live server-side.

---

## 0. Setup (do once, ~5 min)

The Auth DB was rebuilt during the migration fix, so **all users are gone**. Insurance data survives but is owned by dead user IDs — rebuild fresh demo data:

1. **Register a company user** (UI register page) — e.g. `fleet@uber-demo.in` / a strong password.
2. **Register the surveyor** (again, fresh DB) — Suresh: `suresh.kumar@survey-irda.in` / `Suresh.SLA#2026Insp`, licence `IRDAI/SLA/2024/014533`.
3. **Approve Suresh**: login as `admin@tnc.local` / `Admin@12345` → Admin → Approvals (oldest first — your new FIFO sort) → **Approve**.
4. **Create one Active policy** as the company: Quotes → create quote → **Apply** → mock-pay (payment always succeeds: Pending → **Active**, 365-day term). Note the **PolicyNumber** and the **policy GUID** (from the Network tab response, or `GET /api/policies` in Insurance Swagger).
5. **One-time dev-data tweak — backdate the policy start 30 days.** Needed because v3.2 rejects incidents outside the policy term, and Tests 3–4 need incidents in the recent past:
   - Stop InsuranceService (Ctrl+C).
   - Find its DB: `Get-ChildItem "C:\Users\AB13410\dotnet101\TNCInsurance\src" -Recurse -Include "*.db"` → open the Insurance one (DB Browser for SQLite, or the sqlite3 CLI).
   - Run: `UPDATE Policies SET StartDateUtc = datetime('now','-30 days') WHERE PolicyNumber = '<TNCP-P-...>';`
   - Restart InsuranceService. (If datetime formats look odd, copy the existing string and change only the day.)

6. **Get tokens for Swagger:** Auth Swagger → `POST /api/auth/login` as the company → copy `accessToken` → in Insurance Swagger click **Authorize** → `Bearer <token>`. Repeat as Suresh for Tests 6–7.

---

## Golden claim body (copy this; per-test deltas below)

`POST /api/claims` (Insurance Swagger, authorized as the **company**):

```json
{
  "policyId": "<POLICY-GUID>",
  "driverName": "Ravi Teja",
  "driverLicenceNumber": "TS0920210045671",
  "vehicleNumber": "TS09EA4321",
  "passengerName": "Ananya Sharma",
  "passengerContact": "9000012345",
  "passengerCount": 1,
  "additionalPassengersNotes": null,
  "incidentAtUtc": "<YESTERDAY>T04:30:00Z",
  "incidentLocation": "Hitec City signal, Hyderabad",
  "description": "Rear-ended at the signal; bumper and boot dented.",
  "claimedAmountInr": 18000,
  "claimType": "Physical Damage",
  "documentLink": "https://photos.example/fir-copy",
  "appNotInUseDeclared": false,
  "tripEvents": [
    { "eventType": "AppOnline",         "occurredAtUtc": "<YESTERDAY>T04:00:00Z" },
    { "eventType": "RideAccepted",      "occurredAtUtc": "<YESTERDAY>T04:02:00Z" },
    { "eventType": "PassengerPickedUp", "occurredAtUtc": "<YESTERDAY>T04:10:00Z" },
    { "eventType": "RideCompleted",     "occurredAtUtc": "<YESTERDAY>T04:28:00Z" }
  ]
}
```

Canonical trip sequence (FR5.2, exact spellings): **AppOnline → RideAccepted → PassengerPickedUp → RideCompleted** (+ optional AppOffline, final only). Duplicate window: **±2 hours** (config `Claims:DuplicateWindowHours`). Late-intimation threshold: **7 days** (`Claims:LateIntimationWindowDays`). Amount cap: ₹1,00,00,000.

---

## Test 1 — future dates → 400

1a. Golden body but `incidentAtUtc` = **tomorrow**.
✅ **400**: `"Incident date/time cannot be in the future."`

1b. Incident yesterday, but one trip event `occurredAtUtc` = tomorrow.
✅ **400**: `"Trip event 'AppOnline' is dated in the future — it cannot have happened yet."`

## Test 2 — partial trip log → 400

Golden body, but `tripEvents` keeps **only AppOnline + RideCompleted**.
✅ **400**: `"The trip log must contain the complete sequence — AppOnline, RideAccepted, PassengerPickedUp, RideCompleted — in that order (AppOffline optional last). …"`

**Bonus (30s each, all 400):** same four events with times reversed → `"Trip events are out of chronological order."` · same event type twice → `"…each event type at most once."` · made-up type → `"Unknown trip event '…'."`

## Test 3 — duplicate claim → 409 names the first claim

1. File the golden body → **201**. Note `claimNumber` (TNCP-…). ← leave this claim filed for Test 6
2. File again: same `policyId`, `incidentAtUtc` **+45 min**, set `"appNotInUseDeclared": true`, `"tripEvents": null` (shorter body — App-Off skips event validation).
✅ **409**: `"A claim for an incident within +/-2 hours already exists on this policy (TNCP-…). Duplicate filings for one incident are refused at intake."`

## Test 4 — late intimation → 201 but flagged

Golden body, but `incidentAtUtc` = **8–10 days ago** (inside the backdated term), `appNotInUseDeclared: true`, `tripEvents: null`.
✅ **201** with `"isFlagged": true` and `flagReason` containing `"Filed more than 7 days after the incident (late intimation)"`.
✅ UI cross-check: the claim shows the flag chip in My Claims / details.

## Test 5 — apply while Active policy exists → 409, quote NOT converted

1. Company UI: create a **new quote** (note its number).
2. Try to **Apply** it (or `POST /api/policies/apply?quoteId=…`).
✅ **409**: `"Your company already has an Active policy or a Pending application — one active policy per company. …"`
✅ Verify aftermath: My Quotes still lists the quote as **Quoted** (not Converted); My Policies still shows exactly **one** policy. *(The guard runs before quote conversion — this is the double-submit race fix.)*

## Test 6 — pickup → release → re-pickup (the new button)

Authorize Swagger as **Suresh**, or use the UI (`/surveyor/queue`):
1. Queue shows Test 3's claim as `AwaitingSurveyorPickup` → `POST /api/claims/{id}/pickup` → 200.
2. `GET /api/claims/{id}` → status `UnderInvestigation`, **four Pending verification rows** present.
3. Release — UI: investigate screen, **ghost-danger Release button** in the title row (visible only while `UnderInvestigation` + no report) → toast → lands on `/surveyor/assigned`. API: `POST /api/claims/{id}/release` → 200.
4. Queue shows the claim again (`AwaitingSurveyorPickup`); assigned list no longer has it.
5. **Pickup again** → `GET /api/claims/{id}` → exactly **four** Pending rows, **no duplicates**.

## Test 7 — date filters actually filter (the swapped-key fix)

- **Company "My claims"**: set a From/To window that excludes a known claim → list + counts narrow. DevTools Network: `GET /api/claims/company?…&from=…&to=…` — params named **`from`/`to`**.
- **Surveyor queue**: same exercise on `/surveyor/queue` → request shows **`incidentFrom`/`incidentTo`** on `GET /api/claims/queue`.
✅ Pass = params present **and** results really change by incident date. (This is the bug the 94th spec now guards.)

---

**Sign-off:** all 7 green + `dotnet test` green + `npx ng test` 94/94 → v3.2 integration is done. Then Hartford prep.
