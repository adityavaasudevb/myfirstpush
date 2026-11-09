# Backend-Hardening pack — v3.2

This pack implements the agreed mentor change-set across all four services.
Every file is a **full replacement** — paste each over the local file named in
its `// PATH ON YOUR MACHINE:` header (your local copies evolve; these replace
the pack versions).

## What's inside (paste map)

| Pack file | Your local file | Change |
|---|---|---|
| `InsuranceService.Domain/Entities/Claim.cs` | same path | + `PassengerCount`, `AdditionalPassengersNotes` |
| `InsuranceService.Domain/Services/TripEventRules.cs` | same path | + canonical-structure check (complete 4-event sequence), policy-term + log-window flags |
| `InsuranceService.Application/Dtos/ClaimDtos.cs` | same path | + passenger fields on request/details/review DTOs |
| `InsuranceService.Application/Interfaces/ServiceContracts.cs` | same path | + `ReleaseAsync` on `IClaimService` |
| `InsuranceService.Infrastructure/Services/ClaimService.cs` | same path | future-date 400 blocks, canonical-trip-log 400, duplicate 409, late-intimation flag, claimed-amount cap, queue default order (flagged → oldest incident), all paging tiebreakers, `ReleaseAsync` |
| `InsuranceService.Infrastructure/Services/PolicyService.cs` | same path | one-active-policy 409 at apply (before quote conversion), paging tiebreakers |
| `InsuranceService.Infrastructure/Services/DashboardService.cs` | same path | attention list: oldest first + tiebreaker |
| `InsuranceService.Infrastructure/Persistence/InsuranceDbContext.cs` | same path | new column mappings + `(PolicyId, IncidentAtUtc)` index for the duplicate guard |
| `InsuranceService.API/Controllers/ClaimsController.cs` | same path | + `POST {id}/release` route + order notes |
| `QuoteService.Infrastructure/Services/QuoteManagementService.cs` | same path | history list Id tiebreaker; "Converted is terminal" doc note |
| `Frontend/core/models/claim.model.ts` | `src/app/core/models/claim.model.ts` | + passenger fields on request/details; `TRIP_EVENT_CANONICAL` |
| `Frontend/features/claims/file-claim/file-claim.{ts,html}` | same under `src/app/features/claims/` | passenger count + other-passengers fields, future-date caps (`[max]`), preseeded canonical 4-event trip log, completeness helper text |
| `Frontend/features/claims/claim-details/claim-details.html` | same under `src/app/features/claims/` | shows passenger count / other-passenger notes when present |
| `Frontend/features/claims/surveyor/claims-api.service.ts` | `src/app/core/services/claims-api.service.ts` (the Slice-C version) | + `release(id)` |

> Slice C note: your workspace had one `ClaimsApiService` after the pf-3
> unification (the Slice-C full version covering both company + surveyor
> calls). If your local `claim.model.ts` is the Slice-C one, take the Slice-B
> `claim.model.ts` from the Architecture pack and add the two new fields
> (`passengerCount: number | null`, `additionalPassengersNotes: string | null`)
> to its request/details interfaces plus `passengerCount`/`additionalPassengersNotes`
> to the interfaces — the pack's model file shows exactly which lines to add.

## One-off DB migration (Insurance service)

Two new columns on `Claims` + one composite index → schema change, run locally:

```powershell
cd src/Services/Insurance/InsuranceService.API
dotnet ef migrations add IntakeHardeningAndPassengerInfo -p ../InsuranceService.Infrastructure
dotnet ef database update
```

(use your csproj-relative paths if different — same command shape as your first migration).

## One file I can't give you: AuthService pending-sort (v3.2)

Your AuthService wasn't in the workspace, so paste the change by hand — in the
AuthService query backing **pending surveyor registrations** list, order by
registration request date (oldest first, fair FIFO) with an Id tiebreaker:

```csharp
// was (typically):  .OrderByDescending(s => s.CreatedAtUtc)
.OrderBy(s => s.CreatedAtUtc).ThenBy(s => s.Id)
```

If that list's code looks different in your app, send me the file and I'll write
the full-file replacement.

## New config keys (appsettings.json, InsuranceService.API)

```json
"Claims": {
  "LateIntimationWindowDays": 7,
  "DuplicateClaimWindowHours": 2,
  "MaxClaimAmountInr": 20000000
}
```

(`Claims:BoundaryFlagMinutes` already existed.) All have in-code defaults, so the
app runs fine without the JSON block.

## Release button (surveyor UI — optional, 2 small edits)

Endpoint is live (`POST /api/claims/{id}/release`, Surveyor). Wire a button on
the investigation screen:

- `investigate-claim.ts`: add
  ```ts
  readonly releasing = signal(false);
  release(): void {
    this.releasing.set(true);
    this.claimsApi.release(this.id).subscribe({
      next: () => this.router.navigateByUrl('/surveyor/assigned'),
      error: (err) => { this.error.set(responseErrorText(err)); this.releasing.set(false); },
    });
  }
  ```
- `investigate-claim.html` (header row, near the claim title):
  ```html
  <button class="btn-ghost text-danger" (click)="release()" [disabled]="releasing()">
    {{ releasing() ? 'Releasing…' : 'Release back to queue' }}
  </button>
  ```
  (investigate-claim is only reachable for your assigned UnderInvestigation claims, so no visibility guard is needed.)

## Behaviour checks after pasting

1. File a claim with a **future** incident / event date → 400.
2. File a partial trip log (e.g. only AppOnline + RideCompleted) → 400 complete-sequence error.
3. File two claims on one policy with incidents ~1h apart → second gets 409 naming the first claim number; ~3h apart → both accepted.
4. File 8 days after the incident → accepted (201) but flagged "late intimation".
5. Apply for a policy while one is Pending/Active → 409 (quote NOT converted — check the quote still shows Active).
6. Pickup → release → claim back in queue, verifications reset on next pickup.
7. Seeded paged lists still page; equal-timestamp rows never repeat/skip.
