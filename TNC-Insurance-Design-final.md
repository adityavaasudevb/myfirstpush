# TNC (Transport Network Company) Insurance — Design Document v3.0

**Scope statement:** This version was revised after the trainer review of 30
September 2026. The platform keeps four .NET 8 microservices (Auth, Customer,
Quote, Insurance) behind a YARP gateway; PaymentService and its MongoDB store
were removed at the trainer's direction, and premiums/payouts are simulated
inline in InsuranceService (Appendix D, item D3). Cloudinary uploads are
replaced by a single document-link field because the corporate development
laptop cannot reach the service (item D8), and the claims information-request
resubmission loop is deferred (item D9). Policy applications use
straight-through binding: because the product is standardized, the pricing
rules themselves act as the underwriter, and human scrutiny is concentrated on
claims, where money leaves the insurer (Section 4; item D10). All
training-program requirements remain satisfied: Angular with Tailwind and
Vitest, .NET Core microservices with Clean Architecture per service, an API
gateway, role-based navigation, two database technologies (SQLite and SQL
Server), 80% unit-test coverage (xUnit, scoped to the Application and Domain
layers), centralized exception handling, one external API integration
(foreign-exchange rates, with a Polly-retried cached fallback),
search/filter/sort, SOLID principles, continuous integration via GitHub
Actions, and a documented AWS deployment plan.

---

## 1. Abstract

A digital insurance platform for TNC / rideshare fleet insurance — specialty
commercial auto insurance with tiered coverage based on the driver's app
status at the time of an incident. A registered company obtains a non-binding
quote (with live currency conversion through an external exchange-rate API,
falling back to a cached rate if unavailable), applies for a fleet policy
whose premium is computed by deterministic pricing rules (straight-through
binding — no manual review for a standardized product), pays the premium
through a simulated payment step, and files claims with a trip event log and
a supporting document link. Claims pass through an evidence-derived rules
engine that offers decision support only, followed by field-level surveyor
investigation and an Admin's final decision, with payout recorded on approval.
Renewal premiums are experience-rated from each company's historical claims
ratio, mirroring real underwriting practice.

The platform is built with an Angular frontend, a YARP API gateway, and four
.NET 8 microservices, each following Clean Architecture (Domain, Application,
Infrastructure, API):

| Service | Database | Owns |
|---|---|---|
| **AuthService** | SQLite | Users, SurveyorProfiles (JWT and refresh tokens, surveyor approval gate) |
| **CustomerService** | SQL Server | CompanyProfiles |
| **QuoteService** | SQL Server | Quotes (plus the FX-rate client with Polly retry and cached fallback) |
| **InsuranceService** | SQL Server | Policies, Claims, TripEvents, FieldVerifications, SurveyorReports, Dashboard |

```
Angular SPA (:4200) ── /api/** via dev proxy ──> Gateway / YARP (:5000)
   │   /api/auth/** and /api/surveyors/** ──────> AuthService (:5001) ──> SQLite
   │   /api/companies/** ───────────────────────> CustomerService (:5002) ──> SQL Server
   │   /api/quotes/** ──────────────────────────> QuoteService (:5003) ──> SQL Server
   │   /api/policies/**, /api/claims/**, /api/dashboard ──> InsuranceService (:5004) ──> SQL Server
   └── QuoteService (:5003) ──> open.er-api.com (live FX rates; cached fallback on failure)

Inter-service calls (typed HttpClient with a shared handler that forwards the
correlation ID and, where needed, the caller's token; the FX-rate client in
QuoteService is wrapped in Polly retries with a cached-fallback rate):
   InsuranceService ──> CustomerService  (GET /api/companies/me — resolves the caller's company)
   InsuranceService ──> QuoteService     (POST /api/quotes/{id}/convert — validates and marks the origin quote at apply time; GET /api/quotes/stats — dashboard metric)
```

---

## 2. Functional Requirements

Items cut from the first version are deferred rather than deleted. Each is
listed in Appendix D with a restore order, and any requirement that is
affected says so inline.

### FR1 — Authentication and Authorization (AuthService)

- **FR1.1:** Users register and log in through AuthService. Public sign-up
  creates Company-role users only — the role is never accepted from the
  client. Surveyor accounts are created exclusively through FR2A.1, and the
  Admin account is seeded from configuration. Passwords are hashed with
  ASP.NET Core Identity's PasswordHasher.
- **FR1.2:** A successful login issues a short-lived JWT access token (kept in
  memory on the client) carrying the user's ID and role (Company, Surveyor, or
  Admin), plus a refresh token stored in an httpOnly, Secure, SameSite=Lax
  cookie. JWT validation is configured in a shared extension so that role
  claims named "role" are honored by attribute-based role checks and can be
  decoded by the Angular app.
- **FR1.3:** Access to routes and API endpoints is restricted by role. The
  gateway validates every token, and each service validates it again and
  enforces role requirements at the endpoint level.
- **FR1.4 / FR1.5:** The password-reset flow is deferred — see Appendix D,
  item D1.

### FR2 — Company Management (CustomerService)

- **FR2.1:** A Company user creates its company profile (name, registration
  number, contact person, email, phone, fleet size). Only one profile may
  exist per user account (enforced by a unique constraint on the user ID).
- **FR2.2:** A company can view and update only its own profile; requests for
  another company's profile are rejected with HTTP 403.
- **FR2.3:** GET /api/companies/me returns the caller's own profile. It backs
  the Angular profile page and is also called server-to-server by
  InsuranceService to resolve the caller's company (see Section 4).

### FR2A — Surveyor Management (AuthService)

- **FR2A.1:** A surveyor self-registers in one call (email, password, name,
  contact info, IRDAI licence number, licence valid-until date), which creates
  both the user account and the surveyor profile in a single database
  transaction. The licence validity date must be in the future.
- **FR2A.2:** New surveyor accounts are locked to "Pending Approval" status.
- **FR2A.3:** An Admin can approve or reject pending surveyor registrations.
- **FR2A.4:** Only Approved surveyors can access the claims queue.
- **FR2A.5:** Login by a surveyor who is not yet Approved is rejected with
  HTTP 403 and a distinct code (SURVEYOR_PENDING_APPROVAL) so the UI can show
  the correct message.

### FR3 — Quote Management (QuoteService)

- **FR3.1:** A logged-in company can request a non-binding premium quote by
  providing fleet size, desired tier, and optional add-ons.
- **FR3.2:** The system returns the estimated premium for the requested tier
  together with a side-by-side estimate for the alternate tier.
- **FR3.3:** Each quote expires after 7 days (configurable); the status
  changes to Expired when it is read or converted after that date.
- **FR3.4:** An Active quote's ID may be supplied as the origin quote when
  applying for a policy (FR4.1), and conversion happens at that single point
  in the flow: InsuranceService calls QuoteService's conversion endpoint with
  the caller's forwarded JWT (Section 4), which validates the quote — HTTP
  410 if expired, HTTP 409 if already converted — and marks it Converted.
  There is no separate company-facing conversion step; choosing a quote to
  apply from is a client-side action that carries the values the browser
  already holds from the quote history into the application form as prefill.
  The policy stores the originating quote's ID as a plain reference, and the
  premium is always recalculated server-side from the submitted tier, add-ons,
  and fleet size — the prefill is display-only, so tampering with it gains
  nothing.
- **FR3.5:** A company can view its own quote history (paged, filterable by
  status).
- **FR3.6:** Each quote response also shows the estimated premium converted
  to USD and EUR from a live foreign-exchange rate (open.er-api.com) — the
  platform's external-API integration. The call is wrapped in Polly retries;
  on failure the service uses a cached last-known rate (configurable default)
  and marks the response as computed with a fallback rate.

### FR4 — Policy Management (InsuranceService)

- **FR4.1:** A company can apply for a fleet policy either from scratch or
  from an existing Active quote, choosing a coverage tier (Tier A, Period 1 only; or
  Tier B, full coverage) and optional add-ons (Physical Damage, Uninsured
  Motorist, Medical Payments, Rental Car). The request does not carry a
  company ID; InsuranceService resolves the caller's company as described in
  Section 4.
- **FR4.2:** The final premium is calculated server-side from the tier, fleet
  size, and selected add-ons.
- **FR4.3:** New applications start in Pending status. There is no manual
  admin approval step on applications: the product is standardized (fixed
  tiers, fixed limits, server-computed premium), so the pricing rules
  themselves act as the underwriter — straight-through binding. Human review
  is concentrated on claims, where money leaves the insurer, mirroring the
  licensed-surveyor mandate (Section 64UM of the Insurance Act) that applies
  to claim settlement rather than policy issuance.
- **FR4.4:** A policy becomes Active only after a successful simulated
  premium payment (POST /api/policies/{id}/pay; the simulation always
  succeeds, per the trainer decision of 30-Sep-2026, and the company sees a
  success confirmation immediately). On success the start date is set to the
  current instant and the end date to start + 365 days.
- **FR4.5:** A company can cancel a policy only while it is still Pending —
  attempts on any other status return HTTP 409. Cancelling a pending renewal
  is the standard way to decline its adjusted premium.
- **FR4.6:** A company can view its own policies and their details (the
  caller's company is resolved per Section 4 and compared to the policy's
  stored company ID). A policy whose end date has passed reports the
  effective status Expired when it is read — computed on the fly while the
  stored status is still Active, so no scheduled job is used; this is the
  same lazy-expiry pattern as quotes (FR3.3). The stored value is only
  overwritten when a renewal activation writes Expired explicitly (FR4.7).
- **FR4.7 — Renewal.** A company with an Active policy inside the renewal
  window (30 days before the end date, configurable) can renew through a
  single POST /api/policies/{id}/renew call. The server prices the renewal
  with the claims-ratio bands from Section 3 and creates a new Pending policy
  linked (renewed-from) to the policy it renews; only one pending renewal may
  exist per parent policy — further attempts return HTTP 409. The company then
  either pays (accepting the adjusted premium; on activation the renewal
  starts the day after the old policy ends, and the old policy becomes
  Expired) or cancels the pending renewal to decline. A claims ratio above
  100% leaves the premium unadjusted and marks the renewal "Review Required"
  — an informational flag surfaced on the admin dashboard; actioning flagged
  renewals is deferred (item D10).

### FR5 — Claims Management (InsuranceService)

- **FR5.1:** A company files a claim against one of its own Active policies
  (ownership verified per Section 4), supplying driver details (name, licence
  number), passenger details, vehicle number, incident date and time, incident
  location, description, claimed amount, claim type (Third-Party Liability,
  Own Vehicle Damage, Uninsured Motorist, Medical Expense, Rental Car), and a
  single document link (for example a shared Drive folder holding the FIR
  copy, driving-licence copy, and damage photos). The incident location is
  immutable once the claim is submitted and is cross-checked against the FIR
  during investigation. (Real file uploads are deferred — item D8.)
- **FR5.2:** The claim must be accompanied by a trip event log. Either the
  company submits the complete sequence of timestamped events (AppOnline,
  RideAccepted, PassengerPickedUp, RideCompleted/AppOffline), or it declares
  that the app was never turned on for that trip, in which case no event
  validation runs and the claim is classified as App Off.
- **FR5.3:** The event log is validated for chronological sequence; out-of-
  order submissions are rejected with HTTP 400.
- **FR5.4:** The event log is validated for timing plausibility; implausible
  gaps are flagged for mandatory review rather than rejected outright.
- **FR5.5:** The system derives the applicable coverage period by comparing
  the incident time against the event log, instead of accepting a period
  selected by the company.
- **FR5.6:** If the incident time falls within BoundaryFlagMinutes (default 2,
  configurable) of any period boundary event (RideAccepted, PassengerPickedUp,
  or RideCompleted), the claim is flagged for mandatory review.
- **FR5.7:** A rules engine produces a preliminary coverage determination for
  each claim, following the precedence rules in Section 3. It is presented as
  decision support, not a final outcome.
- **FR5.8:** Filing against a policy that is not Active, or for an incident
  date outside the policy term, is rejected at intake with HTTP 409.
- **FR5.9:** A submitted claim enters an open queue visible to all Approved
  surveyors; any surveyor may pick up an unassigned claim. Pickup is atomic —
  implemented as an existence check followed by a single conditional update
  that succeeds only while the status is still AwaitingSurveyorPickup. A
  missing claim returns HTTP 404; a claim that was just assigned returns
  HTTP 409.
- **FR5.10:** The assigned surveyor reviews each evidentiary field
  independently (trip event log, driver information, passenger information,
  documents) and marks it Verified or Suspicious, with an optional note. At
  pickup, all four field-verification records are created in Pending state, so
  "no pending fields" can only be true after genuine review.
- **FR5.11:** A Suspicious verdict does not block the claim; it is recorded as
  a negative signal in the surveyor's report.
- **FR5.12:** The information-request resubmission loop (per-field PATCH with
  a strict mutability whitelist) is deferred — see Appendix D, item D9. Claim
  fields are verified only from the original submission.
- **FR5.13:** The surveyor submits a final report (overall outcome,
  recommendation, recommended payout amount, notes). Submission is rejected
  with HTTP 409 while any field-verification record is still Pending. Each
  claim can have only one report.
- **FR5.14:** The Admin's review screen presents both the rules engine's
  preliminary determination and the surveyor's full report.
- **FR5.15:** The Admin approves or rejects the claim. An override note is
  mandatory whenever the Admin's decision differs from the surveyor's
  recommendation.
- **FR5.16:** The trip event log, the incident location, and the surveyor
  report are immutable once submitted.
- **FR5.17:** A company can view the full status, history, and outcome of its
  claims, including the surveyor's per-field notes.

### FR5 — Claim status state machine

| Status | Entered when | Exited when |
|---|---|---|
| Submitted | Company submits the claim | In the same request, after the rules engine runs |
| AwaitingSurveyorPickup | Rules engine finishes | A surveyor picks the claim up (atomic) |
| UnderInvestigation | Pickup succeeds (four Pending verification records are created) | Report submitted |
| SurveyorReportSubmitted | Report accepted (no Pending verification records remain) | Admin makes the final decision |
| Paid | Admin approves — the payout is simulated in the same request (deterministic success) and the final amount is recorded | Terminal |
| Rejected | Admin rejects | Terminal |

### FR6 — Simulated Payments (inline in InsuranceService)

- **FR6.1:** PaymentService and its MongoDB store were removed at the
  trainer's direction (Appendix D, item D3). Premium payment is a simulated,
  deterministic step inside InsuranceService (POST /api/policies/{id}/pay)
  that always succeeds and immediately confirms to the company; the claim
  payout is recorded in the same request as the Admin's approval, moving the
  claim to Paid with the final amount.
- **FR6.2:** No payment-transaction ledger is persisted in this iteration;
  premium and payout figures are visible on the policy and claim records
  themselves (premium, final payout amount, activation dates).

### FR7 — Admin Dashboard (InsuranceService)

- **FR7.1:** The Admin dashboard aggregates five metrics inside
  InsuranceService: total active policies, total claims this period (calendar
  month), total payout amount (the final amounts of claims that became Paid
  this period), the approval-to-rejection ratio among claims decided this
  period (reported as null when there are zero rejections rather than causing
  an error), and the quote-to-policy conversion rate (converted quotes
  divided by all quotes). The first four are computed locally from the
  Insurance database; the conversion rate comes from GET /api/quotes/stats on
  QuoteService, called with the Admin's JWT forwarded by the shared handler.
  Renewal applications flagged "Review Required" also appear as an attention
  list. A sixth metric (pending surveyor registrations) is deferred (item D2)
  because the Admin already sees those accounts on the Approvals page.

### FR8 — System Reliability

- **FR8.1:** Every service, including the gateway, exposes a /health endpoint.
- **FR8.2:** The FX-rate call from QuoteService to the external exchange-rate
  API uses Polly retry with exponential backoff (three attempts), falling
  back to a cached last-known rate when retries are exhausted (FR3.6). The
  retry path is proven by a unit test (a mocked handler fails twice, succeeds
  on the third, and after exhaustion the fallback rate is returned).
- **FR8.3:** The gateway generates or accepts an X-Correlation-ID header on
  every request, echoes it on the response, and includes it in log scopes. A
  shared handler forwards the header (and the Authorization header where
  needed) on every service-to-service call.
- **FR8.4:** Each service implements centralized exception handling middleware
  that returns a standardized error response containing the correlation ID,
  status code, message, optional details, and timestamp.

### FR9 — Search, Filter and Sort

Sorting is limited to one field per list (additional fields are deferred,
item D7); filtering and search are unchanged.

- **FR9.1:** The Admin can filter the policy list by status and tier, and sort
  it by creation date (ascending or descending). Searching and sorting by
  company name are deferred (item D4).
- **FR9.2:** The Admin can search the claims list by claim ID or vehicle
  number, filter it by status, claim type, and flagged status, and sort it by
  incident date.
- **FR9.3:** A Surveyor can filter the claims queue by incident-date range and
  flagged status, and can view the list of claims assigned to them.
- **FR9.4:** A Company can filter its own quotes, policies, and claims by
  status and date.
- Pagination applies everywhere: a page number (default 1) and page size
  (default 10, maximum 50, enforced by a shared helper).

---

## 3. Business Rules and Configurable Parameters

**Premium calculation.** Base premium = fleet size × ₹15,000 per vehicle per
year × tier multiplier (Tier A = 1.0, Tier B = 1.6). Add-on surcharge = base
premium × sum of the selected add-on rates (Physical Damage 12%, Uninsured
Motorist 5%, Medical Payments 6%, Rental Car 3%). The calculation exists only
on the server — as a pure function in the Domain layer of QuoteService (for
estimates) and InsuranceService (for billing). The Angular app never computes
premiums; it displays server-calculated figures.

**Coverage limits.** Period 1: payout = min(claimed amount, ₹10,00,000) in
both tiers. Periods 2 and 3: payout = min(claimed amount, ₹1,00,00,000),
available only in Tier B. App Off claims are rejected.

**Claim-type to add-on mapping.** Third-Party Liability is base coverage
(always available). Own Vehicle Damage requires the Physical Damage add-on.
Uninsured Motorist claims require the Uninsured Motorist add-on. Medical
Expense claims require Medical Payments. Rental Car claims require the Rental
Car add-on.

**Rules-engine precedence (evaluated in order; the first matching rule
wins):**

1. If the policy is not Active, or the incident date falls outside the policy
   term, the claim is rejected at intake (HTTP 409).
2. Otherwise, if the derived period is App Off, the preliminary decision is
   Reject, with the reason "App not in use".
3. Otherwise, if the derived period is Period 2 or 3 and the policy is Tier A,
   the decision is Reject, with the reason "Period not covered".
4. Otherwise, if the claim type requires an add-on that the policy does not
   include, the decision is Reject, with the reason "Coverage not purchased".
5. Otherwise the decision is Approve, with a preliminary amount of
   min(claimed amount, the period limit).

**Period derivation.** Incident between AppOnline and RideAccepted = Period 1;
between RideAccepted and PassengerPickedUp = Period 2; between
PassengerPickedUp and RideCompleted = Period 3; in all other cases the claim
is App Off.

**Trip-log plausibility flags.** AppOnline to RideAccepted exceeds 4 hours;
RideAccepted to PassengerPickedUp is under 1 minute or over 60 minutes;
PassengerPickedUp to RideCompleted is under 2 minutes or over 6 hours; plus
the boundary-timing flag defined in FR5.6.

**Renewal adjustments.** The renewal window is 30 days before the policy end
date (configurable; set to 365 days for the demo). Claims ratio = total paid
amount of Paid claims on the policy ÷ policy premium. Adjustment bands: below
30% — a 10% discount; 30% to 70% — no change; 70% to 100% — a 15% surcharge;
above 100% — the application is flagged "Review Required" and the premium
stays unadjusted; the flag is informational only in this iteration (surfaced
on the admin dashboard) — no decision endpoint exists for it (Appendix D,
item D10).

**Time limits.** Policy term: 365 days. Quote expiry: 7 days. Access-token
lifetime: 15 minutes (60 minutes in the demo configuration). Refresh-token
lifetime: 7 days. Page size: default 10, maximum 50.

**Exchange rates.** Currency: INR, displayed at quote time alongside USD and
EUR conversions. The live rate is fetched from the external FX API with Polly
retries; the fallback is a configurable default (for example, ₹83.5 per USD),
which is refreshed after every successful call so it stays close to live.

**Time handling.** All timestamps are stored and compared in UTC. The
SQLite-backed Auth database uses UTC DateTime values, because EF Core's SQLite
provider handles DateTimeOffset poorly in comparisons and sorting; all other
services use DateTimeOffset. Policy start and end dates are inclusive at both
ends.

---

## 4. Data Ownership and Cross-Service Rules

- Each service owns and persists its own data (database-per-service). Foreign
  key constraints exist only inside a service's database; cross-service
  references are logical and validated at the application level.
- **Ownership resolution pattern.** When InsuranceService needs the caller's
  company (for policy applications, policy lists, and claim filing), a single
  Application-layer helper calls GET /api/companies/me on CustomerService with
  the caller's JWT forwarded by the shared handler. A successful response
  yields the company ID; a 404 means the user has not created a company
  profile yet, which surfaces to the client as HTTP 400 with instructions. The
  resolved company is then compared locally against the company stored on the
  policy. The client is never trusted to supply a company ID.
- All service-to-service calls use typed HTTP clients registered with the
  shared forwarding handler (correlation ID, and Authorization where needed).
  Polly retries apply to the external FX-rate call in QuoteService (FR3.6),
  with a cached-fallback rate after retries are exhausted.
- There is no event bus and no distributed transaction anywhere in the system.

## 5. Data Model Overview (per service)

**Auth database (SQLite).** User (ID, email, password hash, refresh token,
refresh-token expiry; the user's role is stored in ASP.NET Core Identity's
standard role tables and minted into the JWT at login). SurveyorProfile (ID,
user ID — unique, name, contact info, IRDAI licence number, licence
valid-until date, status, rejection reason).

**Customer database (SQL Server).** CompanyProfile (ID, user ID — unique,
name, registration number, contact person, email, phone, fleet size).

**Quote database (SQL Server).** Quote (ID, quote number — human readable,
owner user ID taken from the caller's token (Sections 4 and 6.3), fleet size,
tier, add-ons, estimated premium, status, expiry date, created date).

**Insurance database (SQL Server).** Policy (ID, policy number — human
readable, company ID, originating quote ID — optional, tier, add-ons, fleet
size, premium, status, start date, end date, renewed-from policy ID —
optional, review-required flag). Claim (ID, claim number — human readable,
policy ID, driver name, driver licence number, vehicle number, passenger
name, passenger contact, incident date/time, incident location — immutable,
description, claimed amount, claim type, document link, app-off flag, derived
period, preliminary decision, preliminary amount, flagged flag, flag reason,
status, assigned surveyor ID — optional, final payout amount — optional,
created date). TripEvent (ID, claim ID, event type, timestamp).
FieldVerification (ID, claim ID, field name, status, note). SurveyorReport
(ID, claim ID — unique, overall outcome, recommendation, recommended amount,
notes, submitted date).

## 6. API Documentation

All errors use the standardized error shape described in FR8.4. Unless marked
Public, every endpoint requires a valid JWT, and role restrictions apply as
noted.

### 6.1 AuthService (port 5001)

| Endpoint | Access | Notes |
|---|---|---|
| POST /api/auth/register `{email, password}` | Public | Creates a Company-role user only; the role is not settable by the client |
| POST /api/auth/login | Public | Issues the access token (user ID and role claims) and sets the httpOnly refresh cookie; surveyor login returns 403 SURVEYOR_PENDING_APPROVAL until the account is approved |
| POST /api/auth/refresh | Public (cookie) | Rotates the token pair |
| POST /api/auth/logout | Cookie | Invalidates the refresh token |
| POST /api/surveyors/register `{email, password, name, contactInfo, irdaiLicenseNumber, licenseValidUntil}` | Public | Creates the user and the pending-approval surveyor profile in one transaction; 400 if the licence validity date is not in the future |
| GET /api/surveyors/pending | Admin | Lists accounts awaiting approval |
| POST /api/surveyors/{id}/approve | Admin | Approves the account |
| POST /api/surveyors/{id}/reject `{reason}` | Admin | Rejects the account |

### 6.2 CustomerService (port 5002)

| Endpoint | Access | Notes |
|---|---|---|
| POST /api/companies `{name, registrationNo, contactPerson, email, phone, fleetSize}` | Company | Creates the company profile for the caller (one per user) |
| GET /api/companies/{id} | Company (own) | Returns the profile; 403 for other companies |
| PUT /api/companies/{id} | Company (own) | Updates mutable profile fields |
| GET /api/companies/me | Company | Returns the caller's own profile; also called by InsuranceService for ownership resolution (Section 4) |

### 6.3 QuoteService (port 5003)

| Endpoint | Access | Notes |
|---|---|---|
| POST /api/quotes `{fleetSize, tier, addOns}` | Company | Returns estimates for both tiers side by side; company taken from the token |
| GET /api/quotes/{id} | Company (own) | Single quote; status flips to Expired lazily on read |
| GET /api/quotes/company | Company (own) | Quote history (status and created-date filters, paging — FR9.4) |
| POST /api/quotes/{id}/convert | InsuranceService (forwarded Company JWT; own quotes only) | Inter-service: marks an Active quote Converted during policy application (FR3.4); 410 if expired, 409 if already converted; returns the quote's stored inputs |
| GET /api/quotes/stats | Admin | Total and converted quote counts; used by the dashboard aggregation |

### 6.4 InsuranceService (port 5004)

| Endpoint | Access | Notes |
|---|---|---|
| POST /api/policies/apply `{originQuoteId?, tier, addOns, fleetSize}` | Company | Server-side premium; company resolved per Section 4; status Pending; response includes the generated policy number; when an origin quote is supplied, QuoteService is called to validate it (410 if expired, 409 if already converted) and it is marked Converted on success |
| GET /api/policies `?status, tier, sortOrder, page` | Admin | Full policy list with filtering, sorting, paging (FR9.1); Review-Required renewals are distinguishable |
| GET /api/policies/company | Company (own) | The caller's policies (status and date filters, paging — FR9.4) |
| GET /api/policies/{id} | Company (own) / Admin | Policy details |
| DELETE /api/policies/{id} | Company (own) | Pending policies only — 409 otherwise; also used to decline a renewal |
| POST /api/policies/{id}/pay | Company (own) | Simulated premium payment (always succeeds); sets start/end dates and activates the policy |
| POST /api/policies/{id}/renew | Company (own, Active, inside the 30-day window) | Creates the Pending renewal priced by the claims-ratio bands (Section 3); 409 if one is already pending; the company then pays to accept or cancels to decline |
| POST /api/claims | Company (own policy) | Validates intake rules, derives the period, runs the rules engine; response carries the claim number plus the preliminary period, decision, amount, and flags |
| GET /api/claims/queue `?isFlagged, incidentFrom, incidentTo, page` | Surveyor (Approved) | Unassigned claims only |
| GET /api/claims/assigned | Surveyor | Claims assigned to the caller |
| POST /api/claims/{id}/pickup | Surveyor (Approved) | 404 if missing, 409 if already assigned; creates the four Pending field-verification records |
| POST /api/claims/{id}/verify-field `{fieldName, status, note?}` | Surveyor (assigned) | Records Verified or Suspicious for one field, plus an optional note |
| POST /api/claims/{id}/report | Surveyor (assigned) | 409 while any field is still Pending; one report per claim |
| GET /api/claims/{id}/review | Admin | Preliminary result plus the surveyor's full report |
| POST /api/claims/{id}/decision `{decision, finalAmount?, overrideNote?}` | Admin | Override note mandatory when differing from the surveyor; on Approve the payout is simulated in the same request (claim becomes Paid, final amount recorded) |
| GET /api/claims/{id} | Company (own) / Admin | Full claim including status history and notes |
| GET /api/claims/company | Company (own) | The caller's claim list (status and date filters, paging — FR9.4) |
| GET /api/claims `?search, status, claimType, isFlagged, sortOrder, page` | Admin | Full claims list with search, filtering, sorting, paging (FR9.2) |
| GET /api/dashboard | Admin | Aggregates the five metrics locally plus GET /api/quotes/stats with the Admin's token forwarded; includes Review-Required renewals as an attention list |

### 6.5 Cross-cutting

Every process (the gateway and all four services) exposes GET /health. The
gateway forwards paths unchanged — there are no path transforms:
/api/auth/** and /api/surveyors/** go to AuthService (5001); /api/companies/**
to CustomerService (5002); /api/quotes/** to QuoteService (5003);
/api/policies/**, /api/claims/**, and /api/dashboard to InsuranceService
(5004).

## 7. Role-Based Access Table

| Role | Pages | Permitted API calls |
|---|---|---|
| **Company** | Dashboard, My Quotes, My Policies, Apply for Policy, File Claim, My Claims | companies (create, read, update, me); quotes (create, read, list); policies (apply, list own, read, pay, renew, cancel); claims (file, read own, list own) |
| **Surveyor** | Dashboard, Claim Queue, Claim Investigation, My Reports | surveyors/register; claims queue; assigned list; pickup; verify-field; submit report |
| **Admin** | Dashboard, Surveyor Approvals, Claims Review | surveyors (pending list, approve, reject); policies (list); claims (list, review, decision); dashboard (includes quote statistics via QuoteService) |
| **Public** | Login, Register, Surveyor Register | auth (register, login, refresh, logout); surveyors/register |

## 8. Exception Handling Strategy

A shared BuildingBlocks library provides the common base exception type
(message only) and the centralized middleware that catches unhandled
exceptions and maps each known exception type to its HTTP status code in a
switch expression, returning the standardized error response. The known
exceptions are:

| Exception | HTTP status | Raised by |
|---|---|---|
| EntityNotFoundException | 404 | Any missing entity (policy, claim, company, quote) |
| UnauthorizedRoleException | 403 | Role or ownership violations |
| UnauthorizedException | 401 | Bad credentials or an invalid/revoked refresh token |
| PolicyStateException | 409 | Claim filed against a non-Active policy (Pending, cancelled, or lapsed) or with an incident date outside the policy term; payment attempted when the policy is not Pending |
| ClaimAlreadyAssignedException | 409 | The losing side of a pickup race |
| ConflictException | 409 | Duplicate quote conversion, existing pending renewal, report submitted too early, duplicate company profile |
| InvalidEventSequenceException | 400 | Out-of-order trip event timestamps |
| ValidationException | 400 | Invalid model input (model-state re-mapping) |
| QuoteExpiredException | 410 | Converting or referencing an expired quote |

Truly unexpected exceptions log the full stack trace on the server and return
a generic 500 message with the correlation ID — internal details are never
returned to the client. On the Angular side, an HTTP interceptor displays the
standardized error as a toast, attaches the access token to every request, and
on a 401 response performs at most one shared token refresh (parallel refresh
calls are coalesced) before retrying the failed request. The application also
refreshes the token once at startup, so reloading the page does not log the
user out.

## 9. Testing

- **Backend (xUnit with coverlet).** The 80% coverage gate applies to the
  Application and Domain assemblies across the four services, matching the
  "focused on business logic" intent. Coverage is measured and enforced with:
  `dotnet test /p:CollectCoverage=true`
  `/p:Include="[*]*.Application;[*]*.Domain" /p:Threshold=80`
  `/p:ThresholdType="line,branch"`.
- Priority test targets are pure business functions covered with table-driven
  theories: the premium calculator (both Quote and Insurance), the full
  rules-engine matrix (tier × period × claim type × add-ons), period
  derivation at boundary edges, plausibility windows, renewal band edges
  (29% / 30% / 70% / 100%), quote expiry, token minting, the Polly retry and
  cached-fallback policy on the FX-rate client (fail twice, succeed on the
  third; after exhaustion, the fallback rate is used), and the atomic claim
  pickup —
  tested with two competing calls against an in-memory SQLite database,
  because EF Core's InMemory provider does not support the conditional
  bulk-update used for the race-safe pickup.
- **Frontend (Vitest).** Configured on day one, before application code
  (using Angular's built-in unit-test builder if the pinned version supports
  it, otherwise the AnalogJS Vite plugin). Coverage thresholds apply to the
  core and service layers; tests cover the route guards, HTTP interceptors,
  the authentication service, and claim-form validation.
- A manual end-to-end rehearsal follows the demo script in Section 11.

## 10. Technology Stack and Solution Layout

The stack: Angular (latest stable) with Tailwind CSS; .NET 8 LTS; Clean
Architecture per service; a YARP API gateway (Ocelot is an acceptable
substitute if the training requires it — the behaviors, namely routing, JWT
validation, correlation-ID injection, and CORS, are the same either way);
SQL Server Express LocalDB (three databases) plus SQLite (Auth); a free
foreign-exchange-rate API (open.er-api.com) as the external integration, with
a Polly-retried, cached-fallback HTTP client; xUnit with coverlet and
Vitest for testing; GitHub Actions for CI; and a documented AWS deployment
runbook. No Docker, no message broker, and no file-upload provider are used.

**Solution layout (created through the Visual Studio UI).** For each of the
four services, four projects under `src/Services/<Name>/`:
`<Name>Service.API` (ASP.NET Core Web API, created with "Use controllers"
enabled), `<Name>Service.Application`, `<Name>Service.Domain`, and
`<Name>Service.Infrastructure` (Class Libraries); plus one xUnit test project
per service under `tests/`. Two further projects: `Gateway` and a
`BuildingBlocks` Class Library. References: each API project references its
Application, Infrastructure, and BuildingBlocks; Application references its
Domain and BuildingBlocks (because application code throws the shared
exceptions); Infrastructure references Application; each test project
references the projects of its service.

**Gateway and environment essentials.** Fixed ports are set in each project's
debug launch profile (Debug menu, "Open debug launch profiles UI"), and the
gateway plus all four services start together via "Configure Startup Projects"
(multiple startup projects). The gateway validates JWTs, adds no path
transforms, and applies CORS restricted to `http://localhost:4200` with
credentials allowed (running the Angular dev server with a proxy configuration
pointed at the gateway port avoids most CORS concerns during development). The
shared JWT-registration extension configures the role-claim mapping used by
both the services and the Angular client. The middleware pipeline order in
every service is: correlation ID, exception handling, CORS, authentication,
authorization, then endpoints. A shared forwarding handler attaches the
correlation ID (and Authorization header where needed) to inter-service
calls.

## 11. Innovation Summary

The project differentiates itself from standard policy-and-claims CRUD systems
in three ways, all achieved with deterministic rules and no AI:

1. **Evidence-derived coverage determination.** The coverage period is derived
   from a validated, timestamped trip event log rather than accepted from the
   claimant, directly targeting the coverage-period disputes that delay real
   rideshare claims; the rules engine structures the evidence a surveyor would
   otherwise assemble manually. The period model is not invented: US state TNC
   statutes (for example, the Texas Insurance Code, Chapter 1954) define the
   same Period 1–3 coverage phases, and identifying the driver's app status at
   the time of a crash is a documented industry source of claim delays — this
   platform resolves that deterministically.
2. **Granular, field-level claims investigation.** Each evidentiary field is
   verified independently with per-field notes before the report can be
   submitted, producing a more auditable investigation trail than whole-claim
   approve/reject flows; a structured information-request resubmission loop is
   a documented next iteration (Appendix D, item D9).
3. **Experience-rated renewal pricing.** Renewal premiums reflect each
   company's historical claims ratio, closing the loop between claims data and
   pricing in the same deterministic style as the rules engine.

The seeded demo data exercises the engine's distinctive paths: a Tier A claim
in Period 2 (rejected, "Period not covered"), a claim type whose add-on was
not purchased (rejected, "Coverage not purchased"), a claim flagged for
incident timing near a period boundary, one claim whose surveyor marked a
field Suspicious yet proceeded to a report, and one paid claim that produces
an 80% claims ratio and therefore a 15% renewal surcharge on its parent
policy.

## 12. Assumptions and Scope Limitations

- Individual drivers do not have accounts; driver details are entered by the
  company when filing a claim.
- There is no real-time trip tracking; trip events are entered retrospectively
  at claim time. The tamper risk of manual timestamps is narrowed — not
  eliminated — through full-sequence reporting, plausibility checks, boundary
  flags, and post-submission immutability.
- Each company holds at most one active policy at a time.
- Claim evidence is shared as a single external document link (for example a
  Drive folder) pasted at filing time, because the corporate development
  laptop cannot reach an upload provider; the database stores the link string
  only, and live-URL/virus validation is out of scope (real uploads are item
  D8).
- Claims are picked up by surveyors from an open queue rather than assigned by
  an admin.
- The Admin account is seeded from configuration rather than self-registered.
- There is no email integration; "notifying the company" means the claim
  status changes, and the company's status-filterable claims list acts as its
  notification inbox.
- Inter-service communication is synchronous HTTP; Polly retries with a
  cached fallback guard the external FX-rate call; no message broker is used.
- Authentication is JWT with refresh tokens; OAuth social login is out of
  scope.
- Fleet underwriting inputs beyond fleet size, tier, and add-ons — VIN-level
  schedules, driver rosters, annual mileage, operating radius, prior loss
  runs — are scoped out; in reality driver and vehicle identity is owned by
  the TNC platform, and this document's company registrationNumber corresponds
  to the company CIN in India. Policy deductibles/compulsory excess are
  omitted from the payout model as a stated scope decision.
- Claim intake asks for one consolidated document link expected to contain
  the standard Indian motor-claim document set (FIR copy, driving-licence
  copy, damage photos), mirroring real claim checklists. Third-party
  vehicle/insurer specifics are recorded in the free-text description and
  gathered by the surveyor through the report's notes.

---

## Appendix D — Deferred Scope

Each item below is self-contained. If time remains after the core build, they
should be restored in this order.

- **D1 — Password reset flow (FR1.4/FR1.5).** Forgot-password and
  reset-password endpoints with a 15-minute reset token (returned directly
  rather than emailed), plus the corresponding Angular pages. Note: check the
  submitted project abstract; if it promised this feature, implement the API
  only and demonstrate it through Swagger.
- **D2 — Full dashboard (FR7.1).** The sixth metric (pending surveyor
  registrations, via a new Admin-only statistics endpoint on AuthService),
  plus graceful degradation ("partial" flag) when a statistics call fails.
- **D3 — PaymentService and MongoDB (FR6).** Removed at the trainer's
  direction on 30 September 2026; premiums and payouts became simulated,
  deterministic steps inside InsuranceService. Restoring a dedicated
  PaymentService (its own MongoDB payment ledger indexed by type and
  reference, Polly-wrapped inter-service calls with a visible 502 failure
  path, and the /api/payments/** gateway route) is the documented
  next-iteration step.
- **D4 — Company-name search and sort (FR9.1).** Requires snapshotting the
  company name onto the policy record at application time (InsuranceService
  already calls CustomerService at that point; the returned name would simply
  be stored).
- **D5 — AWS deployment.** The deployment runbook lives in the README
  regardless; executing it is deferred until the AWS portion of the training
  is complete.
- **D6 — UI polish.** Styling refinements and dashboard charts.
- **D7 — Additional sort fields (FR9).** One sort field per list is the
  committed scope; further fields are restored here.
- **D8 — Real document uploads (FR5.1).** Signed uploads to Cloudinary or S3
  with separate FIR-copy, driving-licence, and damage-photo fields,
  structured FIR number and police-station capture, and backend host
  validation. Blocked on the corporate laptop at build time; the single
  document-link field is the interim intake.
- **D9 — Information-request resubmission loop (former FR5.11, plus the
  PendingCompanyResponse status).** Info Requested as a third per-field
  verdict, the company-facing per-field PATCH endpoint with a strict
  mutability whitelist, surveyor re-review of resubmitted fields, and the
  claim returning to Under Investigation afterwards.
- **D10 — Underwritten binding and Review-Required actioning.** An admin
  decision step on policy applications (the underwritten binding model), and
  a decision endpoint for renewal applications flagged Review Required
  (claims ratio above 100%), at which point that flag becomes actionable
  rather than informational.

## Appendix E — Build Plan (Five Work Blocks)

1. **Setup (the longest block).** Create the solution in Visual Studio as laid
   out in Section 10; set fixed ports and multiple startup projects; add
   health endpoints everywhere; wire the BuildingBlocks middleware, JWT setup,
   pagination helper, and forwarding handler into every service; create EF
   Core contexts and migrations for the four databases; smoke-test the SQL
   Server LocalDB and SQLite connections and the FX-rate endpoint; create
   the Angular workspace with Tailwind and get Vitest passing on a dummy spec
   before writing any components; configure the dev-server proxy; seed the
   Admin account; set up the CI skeleton.
2. **Auth and Customer vertical slice.** Registration, login, refresh, logout;
   surveyor self-registration and admin approval with the pending-status login
   gate; company profile create/read/update plus /api/companies/me; the
   Angular authentication shell (guards, interceptors, startup refresh) with
   login, registration, and profile pages; unit tests for token minting and
   the approval gate.
3. **Quote, Policy, and Payment vertical slice.** Quote endpoints with the
   two-tier estimate (including the FX conversion with its retry/fallback
   client), expiry, history, and conversion; policy application (with the
   ownership call), simulated payment and activation, cancel, and the
   claims-ratio-priced renewal flow; table-driven premium and renewal-band
   tests in both domains; the Angular quote-to-policy flow.
4. **Claims vertical slice.** Event validation, period derivation, and the
   rules engine with the full test matrix; claim filing; the surveyor queue
   and atomic pickup with its concurrency test; four-group field
   verification; report submission with the completeness guard; admin review
   and decision with the simulated payout; the Angular claim, queue,
   investigation, and review screens.
5. **Close-out.** Renewal flow; the dashboard with its two statistics calls;
   search/filter/sort endpoints; seed data for the demo script; coverage to
   the gate; README including the AWS runbook; a green CI run; two complete
   end-to-end rehearsals; deferred items from Appendix D only if hours remain.
