/* ============================================================================
   LANE A - SQL SEED
   Greenfield Fabrication Works - TEST DATA
   ----------------------------------------------------------------------------
   Databases (verified against your environment):
     TNC_CustomerDb · TncQuotes · Tnc_InsuranceDb

   Creates:
     1 company profile (reused by email, never deleted)
     2 quotes · 2 policies · 4 claims · 16 trip events
     4 field verifications · 1 surveyor report
     10 status-history rows · 5 claim-document rows

   Three fixture claims:
     CLM-2026-GFW101  Paid, Rs 3,68,000, full lifecycle
     CLM-2026-GFW102  Flagged, awaiting pickup, no evidence
     CLM-2026-GFW103  CLEAN evidence  -> integrity check: Consistent
     CLM-2026-GFW104  DEFECTIVE evidence -> integrity check: Inconsistent

   BEFORE RUNNING
     1. Register company.greenfield@lynxforge.in through the UI, and create its
        company profile. CompanyProfiles.UserId is the AuthService identity id;
        a row inserted by SQL has no password and cannot be logged into.
        This script reuses that profile if it exists.
     2. Build the API at least once, so bin\Debug\net8.0\App_Data\uploads exists.
     3. Run the pre-flight at the bottom of this header first if you want to see
        what will happen; it is read-only.

   SAFETY
     SET XACT_ABORT ON, one transaction, TRY/CATCH, rollback on any error.
     Fixed ids: this script only ever deletes rows it created itself.
     Safe to re-run.
   ============================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRY
    BEGIN TRANSACTION;

    /* ========================================================================
       0. SCHEMA GUARDS
       Fail before touching anything. Column expectations are the real ones.
       ======================================================================== */
    IF DB_ID(N'TNC_CustomerDb') IS NULL
        THROW 50001, 'Database TNC_CustomerDb was not found.', 1;
    IF DB_ID(N'TncQuotes') IS NULL
        THROW 50002, 'Database TncQuotes was not found.', 1;
    IF DB_ID(N'Tnc_InsuranceDb') IS NULL
        THROW 50003, 'Database Tnc_InsuranceDb was not found.', 1;

    IF COL_LENGTH(N'TNC_CustomerDb.dbo.CompanyProfiles', N'RegistrationNumber') IS NULL
        THROW 50004, 'Expected column CompanyProfiles.RegistrationNumber was not found.', 1;
    IF COL_LENGTH(N'TncQuotes.dbo.Quotes', N'EstimatedPremium') IS NULL
        THROW 50005, 'Expected column Quotes.EstimatedPremium was not found.', 1;
    IF COL_LENGTH(N'TncQuotes.dbo.Quotes', N'CreatedDate') IS NULL
        THROW 50006, 'Expected column Quotes.CreatedDate was not found.', 1;
    IF COL_LENGTH(N'TncQuotes.dbo.Quotes', N'ExpiryDate') IS NULL
        THROW 50007, 'Expected column Quotes.ExpiryDate was not found.', 1;
    IF COL_LENGTH(N'Tnc_InsuranceDb.dbo.Policies', N'PremiumInr') IS NULL
        THROW 50008, 'Expected column Policies.PremiumInr was not found.', 1;
    IF COL_LENGTH(N'Tnc_InsuranceDb.dbo.Claims', N'ClaimNumber') IS NULL
        THROW 50009, 'Expected table Claims was not found.', 1;

    PRINT 'Schema guards passed.';

    /* ========================================================================
       1. COMPANY PROFILE - found by email, reused
       ======================================================================== */
    DECLARE @Profile uniqueidentifier = '9F1C0A10-0001-4A01-9000-000000000001';

    IF NOT EXISTS (SELECT 1 FROM [TNC_CustomerDb].[dbo].[CompanyProfiles]
                   WHERE Email = N'company.greenfield@lynxforge.in')
    BEGIN
        INSERT INTO [TNC_CustomerDb].[dbo].[CompanyProfiles]
        (
            Id, UserId, Name, RegistrationNumber, ContactPerson,
            Email, Phone, FleetSize, CreatedAt, UpdatedAt
        )
        VALUES
        (
            @Profile,
            CAST(NEWID() AS nvarchar(64)),
            N'Greenfield Fabrication Works Pvt Ltd',
            N'U28999TG2017PTC109224',
            N'Meenakshi Sundaram',
            N'company.greenfield@lynxforge.in',
            N'9849012214',
            12,
            '2026-09-26T06:00:00+00:00',
            '2026-09-26T06:00:00+00:00'
        );
        PRINT 'WARNING: profile created WITHOUT a login.';
        PRINT 'Register company.greenfield@lynxforge.in through the UI, or you cannot sign in.';
    END
    ELSE
    BEGIN
        SELECT TOP (1) @Profile = Id
        FROM [TNC_CustomerDb].[dbo].[CompanyProfiles]
        WHERE Email = N'company.greenfield@lynxforge.in'
        ORDER BY CreatedAt;
        PRINT 'Existing company profile found and reused.';
    END;

    DECLARE @QuoteOwner nvarchar(64);
    SELECT TOP (1) @QuoteOwner = UserId
    FROM [TNC_CustomerDb].[dbo].[CompanyProfiles]
    WHERE Id = @Profile;

    IF @QuoteOwner IS NULL OR LTRIM(RTRIM(@QuoteOwner)) = N''
        THROW 50010, 'The company profile has no UserId. Quote ownership cannot be seeded.', 1;

    /* ========================================================================
       2. FIXED IDS - owned by this script only
       ======================================================================== */
    DECLARE @QuoteA  uniqueidentifier = '9F1C0A10-0002-4A01-9000-000000000002';
    DECLARE @QuoteB  uniqueidentifier = '9F1C0A10-0003-4A01-9000-000000000003';
    DECLARE @PolicyA uniqueidentifier = '9F1C0A10-0004-4A01-9000-000000000004';
    DECLARE @PolicyB uniqueidentifier = '9F1C0A10-0005-4A01-9000-000000000005';
    DECLARE @ClaimA1 uniqueidentifier = '9F1C0A10-0006-4A01-9000-000000000006';
    DECLARE @ClaimA2 uniqueidentifier = '9F1C0A10-0007-4A01-9000-000000000007';
    DECLARE @ClaimB1 uniqueidentifier = '9F1C0A10-0008-4A01-9000-000000000008';
    DECLARE @ClaimB2 uniqueidentifier = '9F1C0A10-0009-4A01-9000-000000000009';

    /* ========================================================================
       3. RESET - children before parents, only this script's rows
       ======================================================================== */
    IF OBJECT_ID(N'[Tnc_InsuranceDb].dbo.ClaimDocuments', N'U') IS NOT NULL
        DELETE FROM [Tnc_InsuranceDb].dbo.ClaimDocuments
        WHERE ClaimId IN (@ClaimA1, @ClaimA2, @ClaimB1, @ClaimB2);

    DELETE FROM [Tnc_InsuranceDb].dbo.ClaimStatusHistories
    WHERE ClaimId IN (@ClaimA1, @ClaimA2, @ClaimB1, @ClaimB2);

    DELETE FROM [Tnc_InsuranceDb].dbo.FieldVerifications
    WHERE ClaimId IN (@ClaimA1, @ClaimA2, @ClaimB1, @ClaimB2);

    DELETE FROM [Tnc_InsuranceDb].dbo.SurveyorReports
    WHERE ClaimId IN (@ClaimA1, @ClaimA2, @ClaimB1, @ClaimB2);

    DELETE FROM [Tnc_InsuranceDb].dbo.TripEvents
    WHERE ClaimId IN (@ClaimA1, @ClaimA2, @ClaimB1, @ClaimB2);

    DELETE FROM [Tnc_InsuranceDb].dbo.Claims
    WHERE Id IN (@ClaimA1, @ClaimA2, @ClaimB1, @ClaimB2);

    DELETE FROM [Tnc_InsuranceDb].dbo.Policies
    WHERE Id IN (@PolicyA, @PolicyB);

    DELETE FROM [TncQuotes].dbo.Quotes WHERE Id IN (@QuoteA, @QuoteB);

    PRINT 'Previous Lane A seed rows removed.';

    /* ========================================================================
       4. QUOTES
       Premium = fleet x 15,000 x tier multiplier x (1 + add-on rates)
         A: 12 x 15,000 x 1.6 x 1.17 = 336,960
         B: 12 x 15,000 x 1.6 x 1.21 = 348,480
       ======================================================================== */
    INSERT INTO [TncQuotes].[dbo].[Quotes]
    (Id, QuoteNumber, OwnerUserId, FleetSize, Tier, AddOns,
     EstimatedPremium, Status, CreatedDate, ExpiryDate)
    VALUES
    (
        @QuoteA, N'Q-2026-GFW181', @QuoteOwner, 12, N'Tier B',
        N'["Physical Damage","Uninsured Motorist"]',
        336960.00, N'Converted',
        '2026-09-25T05:30:00+00:00', '2026-10-02T05:30:00+00:00'
    ),
    (
        @QuoteB, N'Q-2026-GFW182', @QuoteOwner, 12, N'Tier B',
        N'["Physical Damage","Medical Payments","Rental Car"]',
        348480.00, N'Active',
        '2026-09-25T05:40:00+00:00', '2026-10-02T05:40:00+00:00'
    );
    PRINT '2 quotes inserted.';

    /* ========================================================================
       5. POLICIES
       Both Active today.
       Policy B ends 20 Nov 2026, so its renewal window is open on 18 Nov.
       ======================================================================== */
    INSERT INTO [Tnc_InsuranceDb].dbo.Policies
    (Id, PolicyNumber, CompanyProfileId, OriginQuoteId, Tier, AddOns, FleetSize,
     PremiumInr, Status, StartDateUtc, EndDateUtc, CreatedAtUtc,
     RenewedFromPolicyId, ReviewRequired)
    VALUES
    (
        @PolicyA, N'POL-2026-GFW001', @Profile, @QuoteA, N'Tier B',
        N'["Physical Damage","Uninsured Motorist"]', 12, 336960.00, N'Active',
        '2026-10-01T10:00:00+00:00', '2027-09-30T10:00:00+00:00',
        '2026-09-30T06:00:00+00:00', NULL, 0
    ),
    (
        @PolicyB, N'POL-2026-GFW002', @Profile, @QuoteB, N'Tier B',
        N'["Physical Damage","Medical Payments","Rental Car"]', 12, 348480.00, N'Active',
        '2025-11-21T10:00:00+00:00', '2026-11-20T10:00:00+00:00',
        '2025-11-21T06:00:00+00:00', NULL, 0
    );
    PRINT '2 policies inserted.';

    /* ========================================================================
       6. CLAIMS
       Column order: the six core intake fields first, then the optional
       passenger detail last. Matches dbo.Claims (26 columns).

       Incident times vs the FIR on CLM-2026-GFW103:
         the FIR prints the occurrence window 10:55-11:20 IST.
         08:10 UTC = 13:40 IST and 13:22 UTC = 18:52 IST are BOTH outside it.

       This is deliberate, and it is safe: the integrity check compares the
       claim's DATE against the documents, not the clock time. It does not parse
       the free-text window on the FIR (see CheckEngine - there is no
       FIR-time rule), so neither claim is flagged for the discrepancy.

       What it DOES compare, and what the fixtures turn on:
         - vehicle registration across documents   (B2: LK3617, claim LK3607)
         - document date vs incident date          (B2: estimate dated 08 Nov)
         - tax vs rate x base                      (B2: Rs 11,160 vs 18% of 48,150)
         - document total vs claimed amount        (B2: 59,310 vs 44,500)
         - duplicate line items                    (B1/B2 reuse check)
         - tow destination vs estimate issuer      (B2: Sri Kalyan vs Meghna)

       If you later add an FIR-time rule, these two claims become test cases
       for it - but do not "fix" the times to make the document agree, because
       the defect in this fixture is the paperwork, not the claim.
       ======================================================================== */
    INSERT INTO [Tnc_InsuranceDb].dbo.Claims
    (
        Id, ClaimNumber, PolicyId, DriverName, DriverLicenceNumber,
        PassengerName, PassengerContact, VehicleNumber,
        IncidentAtUtc, IncidentLocation, Description,
        ClaimedAmountInr, ClaimType, DocumentLink, AppNotInUseDeclared,
        DerivedPeriod, PreliminaryDecision, PreliminaryAmountInr,
        IsFlagged, FlagReason, Status, AssignedSurveyorId,
        FinalPayoutAmountInr, CreatedAtUtc,
        AdditionalPassengersNotes, PassengerCount
    )
    VALUES
    -- A1 - PAID. Drives Policy A's renewal ratio if you renew A.
    (
        @ClaimA1, N'CLM-2026-GFW101', @PolicyA,
        N'Arjun Ravikumar', N'TG0320190112233',
        N'Latha Krishnan', N'9491027781', N'TG12KQ8890',
        '2026-10-21T06:40:00+00:00',
        N'Uppal Ring Road, near Genpact junction, Hyderabad - 500039',
        N'Rear-end collision at a signal; passenger aboard; bumper and boot lid damage. Surveyor negotiated the estimate.',
        412000.00, N'Own Vehicle Damage',
        N'https://evidence.internal/greenfield/CLM-GFW101',
        0, N'Period3', N'Approve', 412000.00, 0, NULL,
        N'Paid', NULL, 368000.00, '2026-10-21T09:15:00+00:00',
        N'Second passenger: minor, no separate details recorded.', 2
    ),
    -- A2 - FLAGGED, boundary. No evidence rows on purpose: proves the audit
    --      refuses a claim that has nothing to check.
    (
        @ClaimA2, N'CLM-2026-GFW102', @PolicyA,
        N'Sandeep Varma', N'TG0320210077661',
        N'Ritika Bose', N'9848036612', N'TG12KQ4417',
        '2026-11-02T13:31:00+00:00',
        N'LB Nagar flyover, descending ramp, Hyderabad - 500074',
        N'Low-speed contact with a divider while en route to pick up the passenger; left door scuffed.',
        96000.00, N'Own Vehicle Damage',
        N'https://evidence.internal/greenfield/CLM-GFW102',
        0, N'Period2', N'Approve', 96000.00, 1,
        N'Incident time within 2 min of a period boundary',
        N'AwaitingSurveyorPickup', NULL, NULL, '2026-11-02T15:00:00+00:00',
        NULL, 1
    ),
    -- B1 - CLEAN. Three documents reconcile with the claim and with each other.
    (
        @ClaimB1, N'CLM-2026-GFW103', @PolicyB,
        N'Karthik Iyer', N'TG1120180044129',
        N'Devi Priya', N'9003321144', N'TG11LK3607',
        '2026-11-10T13:22:00+00:00',
        N'Miyapur X Roads, Hyderabad - 500049',
        N'Left-side collision with an overtaking pick-up while turning into the service lane; door and mirror damaged.',
        71154.00, N'Own Vehicle Damage',
        N'https://evidence.internal/greenfield/CLM-GFW103',
        0, N'Period3', N'Approve', 71154.00, 0, NULL,
        N'AwaitingSurveyorPickup', NULL, NULL, '2026-11-10T14:40:00+00:00',
        N'Second passenger: colleague from the loading site.', 2
    ),
    -- B2 - DEFECTIVE. Same day, 5h48m after B1.
    (
        @ClaimB2, N'CLM-2026-GFW104', @PolicyB,
        N'Prakash Menon', N'TG1120200033118',
        N'Anita Salve', N'9705588120', N'TG11LK3607',
        '2026-11-10T11:10:00+00:00',
        N'Miyapur X Roads, Hyderabad - 500049',
        N'Breakdown and collision on the same stretch; vehicle towed for clutch and body repair.',
        44500.00, N'Own Vehicle Damage',
        N'https://evidence.internal/greenfield/CLM-GFW104',
        0, N'Period3', N'Approve', 44500.00, 0, NULL,
        N'AwaitingSurveyorPickup', NULL, NULL, '2026-11-10T12:30:00+00:00',
        NULL, 1
    );
    PRINT '4 claims inserted.';

    /* ========================================================================
       7. TRIP EVENTS
       ======================================================================== */
    INSERT INTO [Tnc_InsuranceDb].dbo.TripEvents (Id, ClaimId, EventType, OccurredAtUtc)
    VALUES
    (NEWID(), @ClaimA1, N'AppOnline',          '2026-10-21T06:10:00+00:00'),
    (NEWID(), @ClaimA1, N'RideAccepted',       '2026-10-21T06:20:00+00:00'),
    (NEWID(), @ClaimA1, N'PassengerPickedUp',  '2026-10-21T06:30:00+00:00'),
    (NEWID(), @ClaimA1, N'RideCompleted',      '2026-10-21T07:15:00+00:00'),

    (NEWID(), @ClaimA2, N'AppOnline',          '2026-11-02T13:00:00+00:00'),
    (NEWID(), @ClaimA2, N'RideAccepted',       '2026-11-02T13:30:00+00:00'),
    (NEWID(), @ClaimA2, N'PassengerPickedUp',  '2026-11-02T13:45:00+00:00'),
    (NEWID(), @ClaimA2, N'RideCompleted',      '2026-11-02T14:30:00+00:00'),

    (NEWID(), @ClaimB1, N'AppOnline',          '2026-11-10T13:02:00+00:00'),
    (NEWID(), @ClaimB1, N'RideAccepted',       '2026-11-10T13:10:00+00:00'),
    (NEWID(), @ClaimB1, N'PassengerPickedUp',  '2026-11-10T13:18:00+00:00'),
    (NEWID(), @ClaimB1, N'RideCompleted',      '2026-11-10T13:55:00+00:00'),

    (NEWID(), @ClaimB2, N'AppOnline',          '2026-11-10T10:50:00+00:00'),
    (NEWID(), @ClaimB2, N'RideAccepted',       '2026-11-10T11:00:00+00:00'),
    (NEWID(), @ClaimB2, N'PassengerPickedUp',  '2026-11-10T11:05:00+00:00'),
    (NEWID(), @ClaimB2, N'RideCompleted',      '2026-11-10T11:50:00+00:00');
    PRINT '16 trip events inserted.';

    /* ========================================================================
       8. FIELD VERIFICATIONS - A1 completed, so all four are Verified
       ======================================================================== */
    INSERT INTO [Tnc_InsuranceDb].dbo.FieldVerifications (Id, ClaimId, FieldName, Status, Note)
    VALUES
    (NEWID(), @ClaimA1, N'DriverInfo',    N'Verified', N'DL checked against Parivahan; driver is on the fleet roster.'),
    (NEWID(), @ClaimA1, N'PassengerInfo', N'Verified', N'Passenger statement matches the trip log.'),
    (NEWID(), @ClaimA1, N'TripEventLog',  N'Verified', N'Timestamps are plausible; Period 3 confirmed.'),
    (NEWID(), @ClaimA1, N'Documents',     N'Verified', N'FIR copy, estimate and towing receipt are on file.');
    PRINT '4 field-verification rows inserted.';

    /* ========================================================================
       9. SURVEYOR REPORT - only A1 has one; it is Paid
       ======================================================================== */
    INSERT INTO [Tnc_InsuranceDb].dbo.SurveyorReports
    (Id, ClaimId, OverallOutcome, Recommendation, RecommendedAmountInr, Notes, SubmittedAtUtc)
    VALUES
    (
        NEWID(), @ClaimA1, N'Genuine', N'Approve', 368000.00,
        N'Site inspected at the workshop. Estimate Rs 4,12,000; depreciation and betterment deducted, Rs 3,68,000 recommended. Damage pattern is consistent with the FIR.',
        '2026-10-23T09:00:00+00:00'
    );
    PRINT '1 surveyor report inserted.';

    /* ========================================================================
       10. STATUS HISTORY - 10 rows
       A1 walks the full lifecycle to Paid; A2, B1, B2 have intake only.
       ======================================================================== */
    INSERT INTO [Tnc_InsuranceDb].dbo.ClaimStatusHistories
    (Id, ClaimId, FromStatus, ToStatus, ChangedAtUtc, ChangedByUserId)
    VALUES
    (NEWID(), @ClaimA1, NULL,                        N'Submitted',              '2026-10-21T09:15:00+00:00', NULL),
    (NEWID(), @ClaimA1, N'Submitted',                N'AwaitingSurveyorPickup', '2026-10-21T09:15:00+00:00', NULL),
    (NEWID(), @ClaimA1, N'AwaitingSurveyorPickup',   N'UnderInvestigation',     '2026-10-22T05:00:00+00:00', NULL),
    (NEWID(), @ClaimA1, N'UnderInvestigation',       N'SurveyorReportSubmitted','2026-10-23T09:00:00+00:00', NULL),
    (NEWID(), @ClaimA1, N'SurveyorReportSubmitted',  N'Paid',                   '2026-10-24T07:30:00+00:00', NULL),

    (NEWID(), @ClaimA2, NULL,                        N'Submitted',              '2026-11-02T15:00:00+00:00', NULL),
    (NEWID(), @ClaimA2, N'Submitted',                N'AwaitingSurveyorPickup', '2026-11-02T15:00:00+00:00', NULL),

    (NEWID(), @ClaimB1, NULL,                        N'Submitted',              '2026-11-10T14:40:00+00:00', NULL),
    (NEWID(), @ClaimB1, N'Submitted',                N'AwaitingSurveyorPickup', '2026-11-10T14:40:00+00:00', NULL),

    (NEWID(), @ClaimB2, NULL,                        N'Submitted',              '2026-11-10T12:30:00+00:00', NULL);
    PRINT '10 status-history rows inserted.';

    /* ========================================================================
       11. CLAIM DOCUMENTS - 5 rows
       THIS BLOCK IS LOAD-BEARING. The integrity check reads these rows, reads
       the PDF from disk by StoredFileName, and writes its verdict back into
       AiFindingsJson on these same rows. Without them the audit has nothing to
       do and the reviewer sees no documents at all.

       AiStatus / AiModel / AiFindingsJson / AiReviewedAtUtc stay NULL: the
       audit has not run yet. That is what makes the button meaningful.

       StoredFileName must equal the file name in lane-a-sql\documents\ —
       COPY-DOCS.ps1 copies them into App_Data\uploads\<claimId N>\ under
       exactly those names. SizeBytes and Sha256 match the real files.
       ======================================================================== */
    IF OBJECT_ID(N'dbo.ClaimDocuments', N'U') IS NOT NULL
    BEGIN
        INSERT INTO [Tnc_InsuranceDb].dbo.ClaimDocuments
        (Id, ClaimId, DocumentType, OriginalFileName, StoredFileName, ContentType,
         SizeBytes, Sha256, UploadedByUserId, UploadedAtUtc,
         AiStatus, AiModel, AiFindingsJson, AiReviewedAtUtc)
        VALUES
        -- B1 = clean claim: FIR, estimate, towing
        (NEWID(), @ClaimB1, N'FIR',
         N'FIR-01-clean.pdf', N'FIR-01-clean.pdf', N'application/pdf', 46723,
         N'f7554dd1bc7015287eb5e935934253190d7f206934f2fdba4905759487609168',
         NULL, '2026-11-10T14:41:00+00:00', NULL, NULL, NULL, NULL),

        (NEWID(), @ClaimB1, N'RepairEstimate',
         N'RepairEstimate-01-clean.pdf', N'RepairEstimate-01-clean.pdf', N'application/pdf', 46872,
         N'76f70ac5d4b925317b7143a618492bd8121a84e722b2624667f6d5e898d50f7f',
         NULL, '2026-11-10T14:42:00+00:00', NULL, NULL, NULL, NULL),

        (NEWID(), @ClaimB1, N'Other',
         N'TowingReceipt-01-clean.pdf', N'TowingReceipt-01-clean.pdf', N'application/pdf', 46117,
         N'd3103865c972b3b097f06cf554052e2234b70cf2f58fa513d8e3fc20e707b63a',
         NULL, '2026-11-10T14:43:00+00:00', NULL, NULL, NULL, NULL),

        -- B2 = defective claim: estimate and towing only, no FIR
        (NEWID(), @ClaimB2, N'RepairEstimate',
         N'RepairEstimate-02-defects.pdf', N'RepairEstimate-02-defects.pdf', N'application/pdf', 46608,
         N'957cf52f6430bca91f6255f3a41cb8f9cfe678e5de38bbe5f23ef37fe24b7c85',
         NULL, '2026-11-10T12:31:00+00:00', NULL, NULL, NULL, NULL),

        (NEWID(), @ClaimB2, N'Other',
         N'TowingReceipt-02-defects.pdf', N'TowingReceipt-02-defects.pdf', N'application/pdf', 46062,
         N'e8e9632b3641fd090d05caa5409778a652736a90891ed8233bbef5d2c8039827',
         NULL, '2026-11-10T12:32:00+00:00', NULL, NULL, NULL, NULL);

        PRINT '5 claim-document rows inserted.';
        PRINT 'Run COPY-DOCS.ps1 next, or the documents exist in the database but not on disk.';
    END
    ELSE
    BEGIN
        PRINT 'WARNING: ClaimDocuments table was not found.';
        PRINT 'Claims were seeded without evidence. The integrity check will refuse them.';
    END;

    /* ========================================================================
       12. COMMIT
       ======================================================================== */
    COMMIT TRANSACTION;

    PRINT '';
    PRINT '================================================================';
    PRINT 'LANE A SEEDED - Greenfield Fabrication Works';
    PRINT '';
    PRINT 'Policies:';
    PRINT '  POL-2026-GFW001 - Active';
    PRINT '  POL-2026-GFW002 - Active, renewal window open';
    PRINT '';
    PRINT 'Claims:';
    PRINT '  GFW101 - Paid Rs 3,68,000        (no evidence : terminal)';
    PRINT '  GFW102 - Flagged, awaiting       (no evidence : by design)';
    PRINT '  GFW103 - CLEAN   -> run audit -> Consistent';
    PRINT '  GFW104 - DEFECTIVE -> run audit -> Inconsistent';
    PRINT '';
    PRINT 'Next: powershell -File .\COPY-DOCS.ps1';
    PRINT 'Then sign in as the surveyor and open GFW103 and GFW104.';
    PRINT '================================================================';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT '================================================================';
    PRINT 'LANE A SEED FAILED - all changes rolled back';
    PRINT CONCAT('Error number: ', ERROR_NUMBER());
    PRINT CONCAT('Error line:   ', ERROR_LINE());
    PRINT CONCAT('Error message:', ERROR_MESSAGE());
    PRINT '================================================================';
    THROW;
END CATCH;
