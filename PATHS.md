# Where every file goes

Written against your solution as it stands **after Slice A**. Every path below is relative to:

```
TNCInsurance\src\Services\Insurance\
```

If you have not pasted Slice A yet, do that first — Slice B edits files Slice A creates.

---

## Folders you must create

Three. C# does not care about folders, but you do: the next person looking for "the AI code" should
find one folder called `Ai`, not seven files scattered by layer.

| Create this folder | Inside |
|---|---|
| `InsuranceService.Application\Ai\` | the four engine files |
| `InsuranceService.Infrastructure\Ai\` | the provider and the orchestrator |
| `InsuranceService.Tests\` (whole project) | optional — only if you want the tests in-solution |

Nothing else. `Controllers\`, `Interfaces\`, `Constants\` and `Persistence\` already exist.

> **Two folders with the same name is deliberate.** `Application\Ai` holds what the rules *are*
> (schema, prompts, findings, the engine). `Infrastructure\Ai` holds what talks to the world
> (HTTP to Gemini, disk, database). That is the same split as every other feature in this service.

---

## File by file

Source: `DELIVERY\v34-engine\src\Services\Insurance\…` — the zip keeps this exact shape, so you can
drag the `src` folder onto your solution root and let Windows merge.

| # | Copy from `DELIVERY\v34-engine\` | Paste to | Action |
|---|---|---|---|
| 1 | `src\…\Domain\Constants\InsuranceConstants.v34-additions.cs` | `InsuranceService.Domain\Constants\InsuranceConstants.cs` | **Replace what you appended in Slice A** — see the warning below |
| 2 | `src\…\Application\Ai\ExtractionSchema.cs` | `InsuranceService.Application\Ai\ExtractionSchema.cs` | new file, **new folder** |
| 3 | `src\…\Application\Ai\AuditPrompts.cs` | `InsuranceService.Application\Ai\AuditPrompts.cs` | new file |
| 4 | `src\…\Application\Ai\AuditResult.cs` | `InsuranceService.Application\Ai\AuditResult.cs` | new file |
| 5 | `src\…\Application\Ai\CheckEngine.cs` | `InsuranceService.Application\Ai\CheckEngine.cs` | new file |
| 6 | `src\…\Application\Interfaces\AiContracts.cs` | `InsuranceService.Application\Interfaces\AiContracts.cs` | new file, folder exists |
| 7 | `src\…\Infrastructure\Ai\GeminiAiProvider.cs` | `InsuranceService.Infrastructure\Ai\GeminiAiProvider.cs` | new file, **new folder** |
| 8 | `src\…\Infrastructure\Ai\OfflineAiProvider.cs` | `InsuranceService.Infrastructure\Ai\OfflineAiProvider.cs` | new file |
| 9 | `src\…\Infrastructure\Ai\ClaimAuditService.cs` | `InsuranceService.Infrastructure\Ai\ClaimAuditService.cs` | new file |
| 10 | `src\…\API\Controllers\ClaimAuditController.cs` | `InsuranceService.API\Controllers\ClaimAuditController.cs` | new file, folder exists |
| 11 | `src\…\API\Program.cs` | — | **do not paste**; you already replaced `Program.cs` in Slice A. Add six lines instead — §3 |
| 12 | `appsettings.additions.json` (`source/updated/v34/appsettings.additions.json`) | `InsuranceService.API\appsettings.json` | extend the `"Ai"` block — §4 (§4 supersedes it) |

Ten files pasted, one edited in place, one config block extended. No new project. No new package in
`Application` or `Domain`.

---

## 1. The constants file — read this before pasting

In Slice A you **appended four classes** to `InsuranceConstants.cs`:
`ClaimDocumentTypes`, `AiStatuses`, `AiFindingSeverities`, `AiFindingCodes`.

The Slice B file contains all four classes again, with the code list grown from 8 entries to 20.
If you append it as well, the build fails with `CS0101: already contains a definition for…` — and
that error looks alarming on a demo morning.

**Do this:** open `InsuranceConstants.cs`, find the four Slice A classes, delete them, and paste this
file's contents at the same place. The file also starts with `namespace InsuranceService.Domain.Constants;`
so it can stand alone, and it sits inside the same namespace when pasted.

Three codes were removed in this revision because nothing emitted them: `FIR_WINDOW_MISMATCH`,
`LATE_REGISTRATION`, `DOCUMENT_NUMBER_REUSED`. Shipping a constant the engine never raises is a
small lie in a review; better to add it back the day a rule uses it.

---

## 2. `InsuranceService.Infrastructure.csproj` — one package

Only if you set `Ai:Provider` to `vertex`. The default (`inprocess`) needs nothing.

```bash
dotnet add package Google.Apis.Auth --version 1.68.0
```

That is the whole credential story: Application Default Credentials come from that package and from
`gcloud auth application-default login`. **No key in `appsettings.json`, no key in source control.**
Nothing in `Application` or `Domain` gains a dependency — that is the point of putting the HTTP call
in `Infrastructure\Ai`.

If you would rather not touch the csproj, leave `Ai:Provider` as `inprocess`; everything except the
model call still works, and the panel says "AI · offline".

---

## 3. `Program.cs` — six lines in two places

In the registrations block, immediately after the Slice A line
`builder.Services.AddScoped<IClaimDocumentService, ClaimDocumentService>();`:

```csharp
// v3.4 — claim integrity audit (Slice B)
var aiProvider = builder.Configuration["Ai:Provider"] ?? "inprocess";
if (string.Equals(aiProvider, "vertex", StringComparison.OrdinalIgnoreCase))
    builder.Services.AddHttpClient<IAiProvider, GeminiAiProvider>(c =>
        c.Timeout = TimeSpan.FromSeconds(builder.Configuration.GetValue("Ai:TimeoutSeconds", 20)));
else
    builder.Services.AddSingleton<IAiProvider, OfflineAiProvider>();

builder.Services.AddScoped<IClaimAuditService, ClaimAuditService>();
```

And two usings at the top, beside the existing ones:

```csharp
using InsuranceService.Application.Interfaces;   // IAiProvider, IClaimAuditService
using InsuranceService.Infrastructure.Ai;        // GeminiAiProvider, OfflineAiProvider, ClaimAuditService
```

`using InsuranceService.Application.Interfaces;` is already there in your Slice A `Program.cs` — add
the `Infrastructure.Ai` one only.

---

## 4. `appsettings.json` — extend `"Ai"`, don't duplicate it

Slice A already put an `"Ai"` block with `Provider`, `TimeoutSeconds`, `AuditThresholdInr`,
`MaxCallsPerClaim`, `MaxCallsPerDay`. Slice B needs four more keys inside that same block:

```json
"Ai": {
  "Provider": "inprocess",
  "TimeoutSeconds": 20,
  "AuditThresholdInr": 10000,
  "MaxCallsPerClaim": 6,
  "MaxCallsPerDay": 50,

  "ProjectId": "your-gcp-project-id",
  "Location": "global",
  "Model": "gemini-3.8-flash",
  "MaxOutputTokens": 1500,
  "InputPricePerMillionInr": 65,
  "OutputPricePerMillionInr": 330
}
```

Three corrections to what Slice A shipped, all deliberate:

| Key | Slice A | Now | Why |
|---|---|---|---|
| `MaxCallsPerClaim` | 3 | **6** | three documents + one summary is four calls; 3 made the cap reject every claim with three attachments |
| `Location` | `asia-south1` | **`global`** | the Gemini 3.x endpoint is published on `global`; a region endpoint 404s |
| `Model` | `gemini-3.5-flash-lite` | **`gemini-3.8-flash`** | flash, not flash-lite — lite misreads the tax line on the defective estimate in testing |

Duplicate `"Ai"` keys are not an error in `appsettings.json`; the last one silently wins. That is a
worse failure than a build error, so check there is only one.

---

## 5. Tests — two options

**Run them standalone (recommended for today).** The project compiles the engine straight out of the
delivery tree, so no solution changes at all:

```bash
cd DELIVERY\v34-engine\tests\xunit
dotnet test                       # 15/15
```

**Or put them in the solution.** Add a folder `src\Services\Insurance\InsuranceService.Tests\`, copy
`CheckEngineTests.cs`, and use the fragment in `tests\xunit\tests.csproj.fragment.xml` — then delete
`Shims.cs` and `DtosShim.cs`, which exist only because the standalone copy compiles outside the
solution.

Either way, `IsTestProject=true` must be in the csproj. Without it `dotnet test` builds, runs nothing,
and exits 0 — a green tick that means nothing. This caught us during this build.

---

## 6. What is *not* pasted

| Thing | Why not |
|---|---|
| a migration | the four `Ai*` columns already exist — Slice A's `AddClaimDocuments` created them |
| a new table | the claim-level result is serialised into `AiFindingsJson` (duplication noted in the README) |
| a new entity | `ClaimDocument` already carries every field the audit writes |
| a new route | both endpoints nest under `api/claims/{id}/…`, which the gateway already forwards |
| a new microservice | FR constraint, unchanged |
| a change to `ClaimsController` | the audit is its own controller with its own roles and its own failure modes |

---

## 7. Verify in this order

1. **Build.** Any failure here is almost always the duplicate-classes problem in §1.
2. `dotnet test` in `tests\xunit` → 15 passed.
3. `python3 eval.py --provider oracle` in `tests` → `4/4 claims correct`. Needs Python 3.10+ and the
   .NET SDK; costs nothing.
4. Run the API. `GET /health` → Healthy. `GET /api/claims/{id}/integrity` → **204** on a claim that
   has never been checked. 204 is correct, not a bug.
5. Log in as the assigned surveyor, `POST /api/claims/{id}/integrity` with `Ai:Provider=inprocess`
   → **200**, verdict present, `offline: true`, `modelCallsMade: 0`.
6. Switch to `vertex`, `gcloud auth application-default login`, POST again with `?force=true`
   → real findings, `offline: false`, `estimatedCostInr` non-zero but under 2.

Step 5 is the one to show a reviewer. The feature working *without* the model is what makes the
model a component rather than a dependency.
