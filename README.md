# Demo Seed Pack (design doc §11)

Fills all four databases with the full demo story in ~5 minutes. Repeatable: re-running
`seed.sql` deletes and re-inserts the same fixed GUIDs — your 2-minute reset button.

## Prereqs

- All 4 services + gateway running (needed for the 4 register calls + approval).
- Databases created and migrated (TncCustomers, TncQuotes, TncInsurance + Auth SQLite).
- All passwords below satisfy Identity's default rules (≥6 chars, upper, lower, digit, symbol).

## Step 1 — create the users (4 real API calls, via gateway :5000 or AuthService :5001)

```
POST /api/auth/register
{ "email": "company@swiftfleet.in", "password": "SwiftFleet@2026Ride" }

POST /api/auth/register
{ "email": "owner@rajlogistics.in", "password": "RajLogistics#2026Fleet" }

POST /api/surveyors/register
{ "email": "suresh.kumar@survey-irda.in", "password": "Suresh.SLA#2026Insp",
  "name": "Suresh Kumar", "contactInfo": "+91-98490-11477",
  "irdaiLicenseNumber": "IRDAI/SLA/2024/014533", "licenseValidUntil": "2027-12-31" }

POST /api/surveyors/register
{ "email": "pending.surveyor@claimsurvey.in", "password": "Pending.SLA#2026Fresh",
  "name": "Kiran Verma", "contactInfo": "+91-90008-31205",
  "irdaiLicenseNumber": "IRDAI/SLA/2025/028877", "licenseValidUntil": "2028-06-30" }
```

Login as **admin** and approve Suresh only:
`GET /api/surveyors/pending` → `POST /api/surveyors/{id}/approve`.
Leave Kiran pending — he IS the admin-approvals demo content.
Sanity: Kiran's login → 403 `SURVEYOR_PENDING_APPROVAL`.

## Step 2 — paste 3 user GUIDs

Open the Auth SQLite DB (DB Browser / sqlite3) and run:
`SELECT Id, Email FROM AspNetUsers;`
Copy the IDs for the three needed users into the top of `seed.sql`:
`@UserA` (swiftfleet), `@UserB` (rajlogistics), `@Surveyor` (suresh).
*(Note: the "ChangedByUserId" on the admin decision reuses @UserA for simplicity — labels don't surface the email in the demo, so no admin GUID lookup needed.)*

## Step 3 — run `seed.sql` in SSMS

One batch. Prints "SEED DONE". If your CustomerService migration named the table
something other than `CompanyProfiles` (or column names differ), adjust only that
one INSERT block.

## Step 4 — verify the story (expected values)

| Screen / call | Should show |
|---|---|
| Admin dashboard | activePolicies **2** · claimsThisMonth **5** · payout **₹561,600** · approval:reject ratio **null** (FR7.1 zero-rejections edge, visible live!) · conversion **0.33** (1 of 3 quotes) · attention list empty |
| SwiftFleet → My Quotes | `Q-2026-AA0001` Converted · `Q-2026-BB0002` **Expired** (lazy flip on read) · `Q-2026-CC0003` Active ₹207,360 |
| SwiftFleet → My Policies | `POL-2026-AA0001` Active ₹702,000 |
| Claim detail CLM-AA0001 | 5 history rows ending Paid · final **₹561,600** · full event log · 4 Verified fields |
| Claim detail CLM-AA0002 | Documents = Suspicious with note; report notes show the FR5.11 negative-signal line |
| Surveyor queue (Suresh) | 3 claims: CLM-AA0003 **flagged** (boundary), CLM-BB0004 (P2+Tier A → Reject "Period not covered"), CLM-BB0005 (P1 Medical, no add-on → Reject "Coverage not purchased") |
| Admin claims list | 5 claims; `isFlagged=true` → only AA0003; status filter works |
| Admin → Surveyor Approvals | Kiran Verma pending |
| **Renewal demo** | `POST /api/policies/{POL-AA0001}/renew` → ratio **0.8**, band **Surcharge15**, premium **₹807,300.00**; pay it → parent flips Expired, renewal Active from 2027-09-20 |

## Why two companies (honesty note)

§12 says "each company holds at most one active policy at a time" — that's a stated
assumption, not an enforced constraint; nothing in FR4 blocks a second one. The
Period-2 and Coverage-not-purchased rejects need a **Tier A** policy, so they live on
Raj Logistics' policy instead of violating that assumption on SwiftFleet. Two
companies also makes the mixed surveyor queue look real.

## Reset

Just re-run `seed.sql` — the DELETE block cleans the exact GUID set first.
For a full wipe: delete the three SQL Server DBs' rows + Auth SQLite users and redo Step 1.
