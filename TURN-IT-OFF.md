# Vertex on, test, off

You only have `appsettings.json` — that is fine, it is simply the base file and applies to every
environment. Put the `Ai` block there.

## Turn on

`src/InsuranceService/InsuranceService.API/appsettings.json`, **replace** whatever `Ai` block is there
now with:

```json
"Ai": {
  "Provider": "vertex",
  "ProjectId": "higsbx-indintq326sbx",
  "Location": "global",
  "Model": "gemini-3.8-flash",
  "TimeoutSeconds": 30,
  "MaxCallsPerClaim": 6,
  "MaxCallsPerDay": 50,
  "AuditThresholdInr": 10000
}
```

`Location` must be `global` — Gemini 3.x preview models are not served regionally and 404 otherwise.

Watch for: the `Ai` block must sit inside the root object, not inside `"Logging"` or another section.
A trailing comma after the last property is legal in JSON but .NET's config binder tolerates it; a
missing comma is not, and the file fails to load with a `FormatException` at startup, not at first use.

Then:

```powershell
gcloud auth application-default login
gcloud services enable aiplatform.googleapis.com --project higsbx-indintq326sbx
```

Restart the API. Config is read at startup, not per request.

## Test

Swagger → `POST /api/claims/{id}/integrity`. **No `?force=true`.**

The cache skips your documents because:

```csharp
if (!force && documents.All(d => d.AiStatus == AiStatuses.Completed) && ...)
```

Your rows are `Unavailable`, not `Completed`, so extraction runs. `?force=true` is only needed to
re-read a *successful* run.

Expect `offline: false`, `modelCallsMade: 4` (GFW103) and `3` (GFW104).

## Turn off — do all four

Changing the JSON alone is not enough to stop spend. Here is the order that actually stops it:

**1. Change the file back**

```json
"Ai": {
  "Provider": "inprocess",
  "ProjectId": "",
  "Location": "global",
  "Model": "gemini-3.8-flash",
  "TimeoutSeconds": 30,
  "MaxCallsPerClaim": 6,
  "MaxCallsPerDay": 50,
  "AuditThresholdInr": 10000
}
```

`Provider` is the only value that matters — `inprocess` resolves to `OfflineAiProvider`, whose
`IsAvailable` is `false`, so no HTTP call is constructed at all.

**2. Restart the API.** The provider is chosen at startup. Editing the file while the service runs
changes nothing until it reloads.

**3. Revoke the local credential** — this is the step that actually ends the capability, regardless of
what the JSON says:

```powershell
gcloud auth application-default revoke
```

That deletes the ADC token file. After it, even a stray `Provider: vertex` fails at
`GetApplicationDefaultAsync()` and returns a degraded audit rather than a bill.

**4. Optionally disable the API**

```powershell
gcloud services disable aiplatform.googleapis.com --project higsbx-indintq326sbx
```

Only worth doing if you are done for a while. Re-enabling takes a minute and can leave the project in a
state where the first call after re-enable fails once. Step 3 is the one that matters.

## After you turn it off

Your `ClaimDocuments` rows now hold **real** extractions (`AiStatus = Completed`,
`AiFindingsJson` populated). Switching back to `inprocess` and pressing the endpoint again will return
the **cached Vertex result** — the cache check sees `Completed` and short-circuits:

```csharp
if (!force && documents.All(d => d.AiStatus == AiStatuses.Completed) && ...)
{
    var stored = await ReadStoredAsync(claimId, ct);
    if (stored is not null) return stored;
}
```

That is good: your demo keeps the real verdict with zero network. But it also means that after
switching back, a press proves nothing about offline mode. To see the offline behaviour again, either
use a claim whose documents were never successfully extracted, or:

```sql
UPDATE [Tnc_InsuranceDb].dbo.ClaimDocuments
   SET AiStatus = NULL, AiModel = NULL, AiFindingsJson = NULL, AiReviewedAtUtc = NULL
 WHERE ClaimId IN ('9F1C0A10-0008-4A01-9000-000000000008',
                   '9F1C0A10-0009-4A01-9000-000000000009');
```

Then press without `?force=true` and you are back to the honest `NeedsReview`.

## Cost, one more time

Seven calls total for both claims, roughly ₹3.40. If you want a hard ceiling before you start, set a
₹100 budget alert in the console — it is free and takes a minute:

Console → Billing → Budgets & alerts → Create budget → scope to project `higsbx-indintq326sbx` →
amount ₹100 → alert at 50%.

If the project has no billing account you will get `403` with `BILLING_DISABLED` in the error. Nothing
runs, nothing is charged.
