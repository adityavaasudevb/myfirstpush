# Demo seed sheet — two companies, two claims, everything matching

**Rule of this sheet:** every value that appears in a document appears here, character-for-character.
Type from this sheet, not from memory. If a field is not listed, leave it blank or default.

Today = **18 Nov 2026**. Nothing is future-dated. Policies are backdated by SQL; everything else
is created through the UI.

---

## 0. Why the policies cannot come from the frontend

`PolicyService` FR4.4: on payment, **`StartDateUtc = DateTimeOffset.UtcNow`**. A policy created in
the UI today starts today, so a 15 Nov incident falls *outside the term* and the claim is rejected
at intake by `PolicyStateException`.

So: **two `INSERT` statements**, one per company. Premium must equal the formula
`fleet × 15,000 × tier × (1 + Σ add-on rates)`, or a reviewer comparing policy to quote finds the
discrepancy.

---

## 1. Company A — SwiftFleet Mobility (exists in seed)

Register via `POST /api/auth/register`. Complete the company profile in the UI afterwards.

| Field | Value |
|---|---|
| Email | `company@swiftfleet.in` |
| Password | `SwiftFleet@2026Ride` |
| Company name | `SwiftFleet Mobility Pvt Ltd` |
| Registration no. | `U74999TN2019PTC138821` |
| Contact person | `Ananya Rao` |
| Phone | `+91-98450-22110` |
| Fleet size | `25` |

### Policy A (SQL)

| Field | Value |
|---|---|
| Policy number | `POL-2026-AA0001` |
| Tier | `Tier B` |
| Add-ons | `Physical Damage`, `Uninsured Motorist` |
| Fleet | 25 |
| Premium | `702000.00` — 25 × 15,000 × 1.6 × 1.17 |
| Start / End | **2026-09-20 10:00 UTC** → **2027-09-19 10:00 UTC** |
| Status | `Active` |

---

## 2. Company B — Deccan Fleet Services (new)

| Field | Value |
|---|---|
| Email | `fleet@deccanfleet.in` |
| Password | `Deccan@2026Fleet` |
| Company name | `Deccan Fleet Services Pvt Ltd` |
| Registration no. | `U60231TS2021PTC156402` |
| Contact person | `Priya Menon` |
| Phone | `+91-90001-77456` |
| Fleet size | `10` |

### Policy B (SQL)

| Field | Value |
|---|---|
| Policy number | `POL-2026-DD0002` |
| Tier | `Tier B` |
| Add-ons | `Physical Damage`, `Medical Payments` |
| Fleet | 10 |
| Premium | `289000.00` — 10 × 15,000 × 1.6 × 1.18 (PD 0.12 + MedPay 0.06) |
| Start / End | **2026-01-01 10:00 UTC** → **2026-12-31 10:00 UTC** |
| Status | `Active` |

*(No `Rental Car` and no `Uninsured Motorist` — deliberate. If you file a rental claim on this
policy it is Rejected by the rules engine, which is a good thing to show if asked.)*

---

## 3. Claim A — Own Vehicle Damage (the headline demo)

File in the UI as **SwiftFleet**, on **POL-2026-AA0001**.

| Claim field | Value (must match the documents) |
|---|---|
| Driver name | `Ramesh Kumar` |
| Driver licence | `TS0920190045671` |
| Vehicle number | `TS09AB4321` |
| Passenger name | `Meera Iyer` |
| Passenger contact | `+91-98844-10293` |
| Passenger count | `2` |
| Incident date/time | **15 Nov 2026, 09:17** (local = UTC) |
| Incident location | `Down-ramp of Gachibowli flyover, opposite ISB gate, Hyderabad` |
| Claimed amount | **`49560`** |
| Claim type | `Own Vehicle Damage` |
| App not in use | unchecked |

### Trip event log (must give **Period3** = passenger in the car)

| Event | Time |
|---|---|
| AppOnline | 15 Nov, 08:50 |
| RideAccepted | 15 Nov, 09:00 |
| PassengerPickedUp | 15 Nov, 09:10 |
| RideCompleted | 15 Nov, 09:40 |

Incident 09:17 sits inside `[PassengerPickedUp, RideCompleted)` → **Period3**, cap ₹1,00,00,000,
preliminary **Approve ₹49,560**. Not within 2 minutes of a boundary, so no flag.

### Description (paste this exact text)

> Vehicle was stationary at the down-ramp of the Gachibowli flyover with one passenger aboard
> when a Hyundai i20 bearing TS08KL7788 dashed into the rear. Rear bumper, boot lid and right
> tail lamp damaged. Passenger shaken but not injured. Vehicle towed to Sri Balaji Auto Works.

### Documents (upload after filing)

| File | Type to select |
|---|---|
| `FIR-01-clean.pdf` | `FIR` |
| `RepairEstimate-01-clean.pdf` | `RepairEstimate` |
| `TowingReceipt-01-clean.pdf` | `TowingReceipt` |

**What the documents say — must agree with the form above:**

| Document | Value |
|---|---|
| FIR 0142/2026, Madhapur PS | district Hyderabad · occurrence **15-Nov-2026 09:10 → 09:25** · place *Down-ramp of Gachibowli flyover, opposite ISB gate, Hyderabad - 500032* · complainant **Ramesh Kumar**, s/o Venkata Rao, 34, driver · vehicle **TS09AB4321**, Maruti Suzuki Dzire · other vehicle **TS08KL7788** |
| Estimate SBAW/EST/2291 | date **15 Nov 2026** · vehicle **TS09AB4321** · parts ₹30,700 + labour ₹9,800 + supplies ₹1,500 · tax 18% ₹7,560 · **total ₹49,560** |
| Towing GTS/4471 | **15 Nov 2026, 09:40** · tag **TS09AB4321** · VIN MA3EJC32S00M418827 · owner SwiftFleet Mobility Pvt Ltd · from Gachibowli flyover → **Sri Balaji Auto Works** · **₹2,500** |

Expected audit: **no findings**, verdict **Consistent**.
Wrong-path version: swap in `FIR-02-defects.pdf`, `RepairEstimate-02-defects.pdf`,
`TowingReceipt-02-defects.pdf` and expect registration mismatch, date-before-incident, duplicate
line, GST overstated, and a wrong towing destination.

---

## 4. Claim B — Medical Expense (second demo, proves a different money layout)

File as **Deccan Fleet**, on **POL-2026-DD0002**.

| Claim field | Value |
|---|---|
| Driver name | `Farhan Ali` |
| Driver licence | `TS0420230099001` |
| Vehicle number | `TS09EF7788` |
| Passenger name | `Sneha Kulkarni` |
| Passenger contact | `+91-90005-63984` |
| Passenger count | `1` |
| Incident date/time | **16 Nov 2026, 10:17** |
| Incident location | `Gachibowli flyover down-ramp, Hyderabad` |
| Claimed amount | **`35176`** |
| Claim type | `Medical Expense` |

### Trip event log (also Period3)

| Event | Time |
|---|---|
| AppOnline | 16 Nov, 09:50 |
| RideAccepted | 16 Nov, 10:00 |
| PassengerPickedUp | 16 Nov, 10:10 |
| RideCompleted | 16 Nov, 10:40 |

### Description

> Passenger injured when the vehicle braked hard at the Gachibowli flyover down-ramp. Treated at
> Sri Sai Multispeciality Hospital, admitted overnight, discharged 17 November.

### Documents

| File | Type |
|---|---|
| `MedicalBill-01-clean.pdf` | `MedicalBill` |
| `MedicalBill-03-pharmacy.pdf` | `Other` |

**What the bill says — must agree:**

| Field | Value |
|---|---|
| Bill SSMH/IP/8817 | patient **Ramesh Kumar**, 34 / Male · admission **16 Nov 2026, 10:30** · discharge **17 Nov 2026, 10:00** · bill date **17 Nov 2026, 12:15** |
| Totals | professional fees ₹8,400 + billing heads ₹27,776 = **₹36,176** · discount ₹1,000 · **final ₹35,176** · paid ₹35,176 · balance ₹0 |
| Pharmacy INV-26001026 | 17 Nov 2026 · total ₹633.60 · discount ₹40 · net **₹593.60** |

> **Known inconsistency, on purpose:** the bill names **Ramesh Kumar** while the claim is filed for
> **Farhan Ali**. The patient-name check must flag it. Either accept that as your "one finding"
> demo, or I regenerate the bill with Farhan Ali's name — your call. Everything else matches.

The pharmacy invoice has **no patient name** — that is realistic (walk-in billing) and the check
must treat it as *not verifiable*, not as a mismatch.

---

## 5. Known traps in this data (do not "fix" them)

| Trap | Why it is there |
|---|---|
| Bill patient ≠ claim driver | Proves the name check works |
| Pharmacy has no name | Proves missing data is not a finding |
| Claim A and Claim B are different days | The duplicate guard is ±2h **per policy**; same-day claims would 409 |
| Deccan has no Rental Car add-on | A rental claim on it is correctly Rejected |
| FIR occurrence is a window, not a point | The check is *incident inside window*, not equality |
| Estimate has no patient name | Not every document carries every field |

---

## 6. What still has to be built

1. Extraction schema + deterministic check engine (me, next)
2. Eval harness over all 11 documents — precision/recall on planted defects (me)
3. Evidence panel: document list, viewer, findings, verdict chip (me)
4. Upload UI on `file-claim` (me)
5. Timeline strip from trip events + document dates (me)
6. Doc v3.4 + model card + eval table (me)
7. Rehearsal with the network unplugged (you)
