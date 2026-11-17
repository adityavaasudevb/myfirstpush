# v3.4 Slice A — evidence attachments (FR5.1 amended)

**Goal of this slice:** a company can attach real evidence files at filing; the company,
the assigned surveyor and any admin can all view them. No AI yet — that's Slice B.

---

## Files in this slice

| File in this package | Paste to |
|---|---|
| `src/Services/Insurance/InsuranceService.Domain/Entities/ClaimDocument.cs` | `src/Services/Insurance/InsuranceService.Domain/Entities/ClaimDocument.cs` |
| `src/Services/Insurance/InsuranceService.Domain/Constants/InsuranceConstants.v34-additions.cs` | **Append the classes** to `Domain/Constants/InsuranceConstants.cs` (then delete the additions file) |
| `src/Services/Insurance/InsuranceService.Application/Dtos/ClaimDocumentDtos.cs` | `Application/Dtos/ClaimDocumentDtos.cs` |
| `src/Services/Insurance/InsuranceService.Application/Interfaces/DocumentContracts.cs` | `Application/Interfaces/DocumentContracts.cs` |
| `src/Services/Insurance/InsuranceService.Infrastructure/Services/ClaimDocumentService.cs` | `Infrastructure/Services/ClaimDocumentService.cs` |
| `src/Services/Insurance/InsuranceService.Infrastructure/Persistence/InsuranceDbContext.cs` | **Replace** `Infrastructure/Persistence/InsuranceDbContext.cs` (v3.3 + v3.4 lines; diff is one DbSet + one mapping block) |
| `src/Services/Insurance/InsuranceService.API/Controllers/ClaimDocumentsController.cs` | `API/Controllers/ClaimDocumentsController.cs` |
| `src/Services/Insurance/InsuranceService.API/Program.cs` | **Replace** `API/Program.cs` (v3.4 lines marked in comments) |
| `appsettings.additions.json` | **Manually paste** the two blocks into `API/appsettings.json` (comments stripped) |

---

## Steps

1. Paste the files above. Build.
2. Add the two config blocks.
3. **Create the migration — and open it before applying** (War 1 gate):

```bash
cd src/Services/Insurance/InsuranceService.API
dotnet ef migrations add AddClaimDocuments -p ../InsuranceService.Infrastructure -s .
```

Open `Migrations/*_AddClaimDocuments.cs` and confirm `Up()` contains
`CreateTable(name: "ClaimDocuments", ...)` with columns `Id, ClaimId, DocumentType,
OriginalFileName, StoredFileName, ContentType, SizeBytes, Sha256, UploadedByUserId,
UploadedAtUtc, AiStatus, AiModel, AiFindingsJson, AiReviewedAtUtc`.

If `Up()` is empty or missing columns → the migration is hollow (War 1). **Do not apply it.**

4. `dotnet ef database update -p ../InsuranceService.Infrastructure -s .`
5. Run the API, then verify in Swagger:

| Check | Expected |
|---|---|
| `GET /health` | `{"status":"Healthy","service":"InsuranceService"}` |
| `POST /api/claims/{id}/documents` with a PDF + `documentType=RepairEstimate` | **201**, JSON with `sha256` stored |
| `GET /api/claims/{id}/documents` | the document listed |
| `GET /api/claims/{id}/documents/{docId}` | PDF renders inline in the browser |
| Upload an `.exe` renamed to `.pdf` | **400** — magic bytes fail, extension is irrelevant |
| Upload 6 MB file | **400** — size cap |
| Upload as a surveyor | **403** |
| Upload after the surveyor picks the claim up | **409** — "Evidence is frozen at surveyor pickup (FR5.16)" |
| Upload to another company's claim | **403** |

6. Confirm the file landed on disk:
`bin/Debug/net8.0/App_Data/uploads/<claimId-as-32-hex>/<guid>.pdf`

---

## What this does to the design doc

Nothing yet — the doc is written after the code works (your rule). When we get there:

- **FR5.1** becomes: *"… and optional evidence documents (FIR, repair estimate, medical
  bill, rental invoice, other), uploaded at filing. A legacy external link is still
  accepted for claims created before v3.4."*
- **Appendix D, D8** is narrowed: *"(a) implementation delivered in v3.4 — local storage,
  server-side type sniffing, immutable after pickup. Remaining: cloud storage, virus
  scanning, structured FIR fields."*
- **FR5.16** gains one sentence: *"Evidence documents are immutable once a surveyor picks
  the claim up."*
- No FR is renumbered. No new status. No state-machine change.

---

## Deliberate limits (say these out loud if asked)

- **Local disk, not cloud.** One instance, files survive restarts, no network dependency.
  Cloud/object storage is still D8.
- **Max 5 MB per file, 10 files per claim.** Enough for a demo, and it stops the browser
  multipart from timing out.
- **PDF/JPG/PNG only**, verified by magic bytes. No Office documents — they are the
  main vector for malicious payloads and the demo does not need them.
- **Evidence freezes at pickup.** Enforced server-side with a 409, not just hidden in the UI.
- **No virus scanning.** Explicitly out of scope, stated in D8.
