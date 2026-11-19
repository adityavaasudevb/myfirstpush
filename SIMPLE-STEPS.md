# Do these five things, in order

Nothing to install. Nothing to edit. No ids to copy.

---

## 1. Run `STEP-1-park-profile.sql` in SSMS

Press F5. It prints the form values you'll need in the next step.

## 2. Log in to the app as the company

`company.greenfield@lynxforge.in` / `GFW#2026Test`

You'll see the **fleet-profile form** — that's the screen you skipped. Fill it in with exactly:

```
Company name         Greenfield Fabrication Works Pvt Ltd
Registration number  U28999TG2017PTC109224
Contact person       Meenakshi Sundaram
Email                company.greenfield@lynxforge.in
Phone                9849012214
Fleet size           12
```

Submit. You should land on the dashboard.

## 3. Run `STEP-2-cleanup.sql` in SSMS

Press F5. It prints `MY POLICIES (expect 2)` and `MY CLAIMS (expect 4)`.
If those say 2 and 4, the profile problem is finished.

## 4. Copy the PDFs

```powershell
cd C:\Users\AB13410\Downloads\lane-a-sql\lane-a-sql
powershell -ExecutionPolicy Bypass -File .\COPY-DOCS.ps1
```

Ignore the Node module `.db` files the search found — those are Angular's, not yours.
Your Auth database is `src\AuthService\AuthService.API\TNC_Auth.db`, and you don't need to open it.

## 5. Run the audits

Log in as the surveyor, open the two claims:

| Claim | Press "Run integrity check" | Expect |
|---|---|---|
| GFW103 | once | **Consistent** |
| GFW104 | once | **Inconsistent** — 5 findings |

---

## If step 2 doesn't show the form

Sign out and sign in again. The check happens at login.

## If step 3 says "no profile for this email"

The form didn't submit. Go back to step 2.

---

## Why this order

The profile row must be created by the app, because that's the only thing that knows your user id.
The seed's row was written by SQL, so its user id is a guess — and it was holding the email address,
which is what stopped the form from working in the first place. Step 1 hands the email back, step 2
lets the app claim it, step 3 attaches the 2 policies and 4 claims.
