-- ============================================================================
-- TNC INSURANCE — DEMO SEED (design doc Section 11)
-- One batch: paste the 3 user GUIDs below (from the Auth SQLite DB), run in SSMS.
-- Idempotent: fixed GUIDs are DELETEd first, so re-running = instant reset.
-- All premium math matches Section 3; all statuses match the FR state machines.
-- UTC timestamps. Today in the demo timeline: 2026-10-05 (IST).
-- ============================================================================

DECLARE @UserA nvarchar(64) = 'PASTE-SWIFTFLEET-USER-ID';      -- company@swiftfleet.in
DECLARE @UserB nvarchar(64) = 'PASTE-RAJLOGISTICS-USER-ID';    -- owner@rajlogistics.in
DECLARE @Surveyor nvarchar(64) = 'PASTE-APPROVED-SURVEYOR-ID'; -- suresh.kumar@survey-irda.in

-- Fixed entity GUIDs (hex-safe, human-greppable)
DECLARE @ProfileA uniqueidentifier = 'aa000001-0000-4000-8000-000000000001';
DECLARE @ProfileB uniqueidentifier = 'bb000002-0000-4000-8000-000000000002';
DECLARE @QuoteC  uniqueidentifier = 'ee000001-0000-4000-8000-000000000001'; -- Converted (origin of main policy)
DECLARE @QuoteE  uniqueidentifier = 'ee000002-0000-4000-8000-000000000002'; -- lazily Expired
DECLARE @QuoteA  uniqueidentifier = 'ee000003-0000-4000-8000-000000000003'; -- Active today
DECLARE @PolA    uniqueidentifier = 'aa000001-0000-4000-9000-000000000001'; -- SwiftFleet Tier B 702,000
DECLARE @PolB    uniqueidentifier = 'bb000002-0000-4000-9000-000000000002'; -- Raj Tier A 600,000
DECLARE @ClmPaid uniqueidentifier = 'cc000001-0000-4000-9000-000000000001';
DECLARE @ClmSusp uniqueidentifier = 'cc000002-0000-4000-9000-000000000002';
DECLARE @ClmFlag uniqueidentifier = 'cc000003-0000-4000-9000-000000000003';
DECLARE @ClmTier uniqueidentifier = 'cc000004-0000-4000-9000-000000000004';
DECLARE @ClmMed  uniqueidentifier = 'cc000005-0000-4000-9000-000000000005';

-- ----------------------------------------------------------------  RESET  --
USE TncInsurance;
DELETE FROM ClaimStatusHistories WHERE ClaimId IN (@ClmPaid,@ClmSusp,@ClmFlag,@ClmTier,@ClmMed);
DELETE FROM FieldVerifications  WHERE ClaimId IN (@ClmPaid,@ClmSusp,@ClmFlag,@ClmTier,@ClmMed);
DELETE FROM SurveyorReports     WHERE ClaimId IN (@ClmPaid,@ClmSusp,@ClmFlag,@ClmTier,@ClmMed);
DELETE FROM TripEvents          WHERE ClaimId IN (@ClmPaid,@ClmSusp,@ClmFlag,@ClmTier,@ClmMed);
DELETE FROM Claims              WHERE Id     IN (@ClmPaid,@ClmSusp,@ClmFlag,@ClmTier,@ClmMed);
DELETE FROM Policies            WHERE Id     IN (@PolA,@PolB);
USE TncQuotes;    DELETE FROM Quotes WHERE Id IN (@QuoteC,@QuoteE,@QuoteA);
USE TncCustomers; DELETE FROM CompanyProfiles WHERE Id IN (@ProfileA,@ProfileB);

-- -------------------------------------------------------  COMPANIES (SQL)  --
USE TncCustomers;
INSERT INTO CompanyProfiles (Id, UserId, Name, RegistrationNo, ContactPerson, Email, Phone, FleetSize, CreatedAt, UpdatedAt)
VALUES
(@ProfileA, @UserA, N'SwiftFleet Mobility Pvt Ltd', N'U74999TN2019PTC138821', N'Ananya Rao', N'company@swiftfleet.in', N'+91-98450-22110', 25, '2026-09-15T09:00:00+00:00', '2026-09-15T09:00:00+00:00'),
(@ProfileB, @UserB, N'Raj Logistics & Cargo Pvt Ltd', N'U60231TS2021PTC156402', N'Rajesh Kumar', N'owner@rajlogistics.in', N'+91-90001-77456', 40, '2026-09-16T09:00:00+00:00', '2026-09-16T09:00:00+00:00');

-- Note: if your migration named the table differently, adjust these two names only.

-- ----------------------------------------------------------  QUOTES (SQL)  --
USE TncQuotes;
-- Converted (origin of the main policy): 25 x 15,000 x 1.6 x 1.17 = 702,000
INSERT INTO Quotes (Id, QuoteNumber, OwnerUserId, FleetSize, Tier, AddOns, PremiumInr, Status, CreatedAtUtc, ExpiresAtUtc)
VALUES
(@QuoteC, N'Q-2026-AA0001', @UserA, 25, N'Tier B', N'["Physical Damage","Uninsured Motorist"]', 702000.00, N'Converted', '2026-09-18T05:00:00+00:00', '2026-09-25T05:00:00+00:00'),
-- Stored Active but past expiry -> reads as Expired (lazy, FR3.3): 12 x 15,000 x 1.12 = 201,600
(@QuoteE, N'Q-2026-BB0002', @UserA, 12, N'Tier A', N'["Physical Damage"]', 201600.00, N'Active', '2026-09-20T05:00:00+00:00', '2026-09-27T05:00:00+00:00'),
-- Fresh Active quote: 8 x 15,000 x 1.6 x 1.08 = 207,360
(@QuoteA, N'Q-2026-CC0003', @UserA, 8, N'Tier B', N'["Uninsured Motorist","Rental Car"]', 207360.00, N'Active', '2026-10-05T06:00:00+00:00', '2026-10-12T06:00:00+00:00');

-- -----------------------------------------------------  POLICIES (SQL Srv) --
USE TncInsurance;
INSERT INTO Policies
(Id, PolicyNumber, CompanyProfileId, OriginQuoteId, Tier, AddOns, FleetSize, PremiumInr, Status, StartDateUtc, EndDateUtc, CreatedAtUtc, RenewedFromPolicyId, ReviewRequired)
VALUES
(@PolA, N'POL-2026-AA0001', @ProfileA, @QuoteC, N'Tier B', N'["Physical Damage","Uninsured Motorist"]', 25, 702000.00, N'Active', '2026-09-20T10:00:00+00:00', '2027-09-19T10:00:00+00:00', '2026-09-20T09:00:00+00:00', NULL, 0),
(@PolB, N'POL-2026-BB0002', @ProfileB, NULL, N'Tier A', N'[]', 40, 600000.00, N'Active', '2026-09-01T10:00:00+00:00', '2027-08-31T10:00:00+00:00', '2026-09-01T09:00:00+00:00', NULL, 0);

-- ----------------------------------------------------------  CLAIMS ROWS  --
-- (1) PAID claim — the renewal story. Own Vehicle Damage, claimed 650,000 (P3
--     cap 1Cr), surveyor negotiated to 561,600 -> ratio 561600/702000 = 0.80
INSERT INTO Claims
(Id, ClaimNumber, PolicyId, DriverName, DriverLicenceNumber, PassengerName, PassengerContact, VehicleNumber,
 IncidentAtUtc, IncidentLocation, Description, ClaimedAmountInr, ClaimType, DocumentLink, AppNotInUseDeclared,
 DerivedPeriod, PreliminaryDecision, PreliminaryAmountInr, IsFlagged, FlagReason, Status, AssignedSurveyorId,
 FinalPayoutAmountInr, CreatedAtUtc)
VALUES
(@ClmPaid, N'CLM-2026-AA0001', @PolA, N'Venkat Prasad', N'TS0920190045671', N'Meera Iyer', N'+91-98844-10293', N'TS09UB4821',
 '2026-10-01T14:40:00+00:00', N'ORR Service Road, Gachibowli, Hyderabad', N'Rear-end collision while passenger on board exiting ORR; bumper and boot damage, third-party bike also damaged.', 650000.00, N'Own Vehicle Damage', N'https://drive.google.com/drive/folders/swiftfleet-clm-aa0001', 0,
 N'Period3', N'Approve', 650000.00, 0, NULL, N'Paid', @Surveyor, 561600.00, '2026-10-01T16:00:00+00:00'),

-- (2) Suspicious-but-proceeded (FR5.11) — awaiting admin decision
(@ClmSusp, N'CLM-2026-AA0002', @PolA, N'Arjun Nair', N'TS0920220078452', N'Kavya Menon', N'+91-97310-55821', N'TS09UB7756',
 '2026-09-28T11:40:00+00:00', N'HITEC City Main Road, Madhapur, Hyderabad', N'Side-swipe during lane change with passenger aboard; door and fender damage; FIR filed at Madhapur PS.', 480000.00, N'Own Vehicle Damage', N'https://drive.google.com/drive/folders/swiftfleet-clm-aa0002', 0,
 N'Period3', N'Approve', 480000.00, 0, NULL, N'SurveyorReportSubmitted', @Surveyor, NULL, '2026-10-02T08:00:00+00:00'),

-- (3) Boundary-flagged (FR5.6) — incident 1 min after RideAccepted; Period2 on
--     Tier B approves, but sits flagged in the queue (FR5.4)
(@ClmFlag, N'CLM-2026-AA0003', @PolA, N'Imran Sheikh', N'TS0920210033987', N'Divya Reddy', N'+91-96520-88734', N'TS09UC3320',
 '2026-10-03T18:01:00+00:00', N'Wipro Circle Junction, Gachibowli, Hyderabad', N'Minor collision seconds after accepting ride near Wipro Circle; timing noted against event timestamps.', 300000.00, N'Own Vehicle Damage', N'https://drive.google.com/drive/folders/swiftfleet-clm-aa0003', 0,
 N'Period2', N'Approve', 300000.00, 1, N'Incident time within 2 min of a period boundary', N'AwaitingSurveyorPickup', NULL, NULL, '2026-10-03T19:00:00+00:00'),

-- (4) Tier A + Period 2 -> rules precedence #3: "Period not covered" (queue)
(@ClmTier, N'CLM-2026-BB0004', @PolB, N'Santosh Yadav', N'TS0420180011223', N'Pooja Sharma', N'+91-94410-36258', N'TS07HD9021',
 '2026-10-02T08:05:00+00:00', N'Necklace Road, Khairatabad, Hyderabad', N'Van hit median while en route to pickup; third-party liability claimed by property owner for railing damage.', 900000.00, N'Third-Party Liability', N'https://drive.google.com/drive/folders/rajlog-clm-bb0004', 0,
 N'Period2', N'Reject', NULL, 0, NULL, N'AwaitingSurveyorPickup', NULL, NULL, '2026-10-02T12:00:00+00:00'),

-- (5) Tier A + Period 1 + Medical Expense -> precedence #4: "Coverage not
--     purchased" (queue). Period 1 chosen deliberately so rule #3 does not fire first.
(@ClmMed, N'CLM-2026-BB0005', @PolB, N'Farhan Ali', N'TS0420230099001', N'Sneha Kulkarni', N'+91-90005-63984', N'TS07HD4417',
 '2026-10-04T07:20:00+00:00', N'Secunderabad Club, Trimulgherry, Hyderabad', N'Scooter collision while app online awaiting ride request; rider claims medical expense for pillion rider.', 150000.00, N'Medical Expense', N'https://drive.google.com/drive/folders/rajlog-clm-bb0005', 0,
 N'Period1', N'Reject', NULL, 0, NULL, N'AwaitingSurveyorPickup', NULL, NULL, '2026-10-04T09:30:00+00:00');

-- --------------------------------------------------------  TRIP EVENT LOG  --
INSERT INTO TripEvents (Id, ClaimId, EventType, OccurredAtUtc) VALUES
-- (1) 14:00 online, 14:10 accepted, 14:20 pickup, 15:05 complete; incident 14:40 -> P3
(NEWID(), @ClmPaid, N'AppOnline',          '2026-10-01T14:00:00+00:00'),
(NEWID(), @ClmPaid, N'RideAccepted',       '2026-10-01T14:10:00+00:00'),
(NEWID(), @ClmPaid, N'PassengerPickedUp',  '2026-10-01T14:20:00+00:00'),
(NEWID(), @ClmPaid, N'RideCompleted',      '2026-10-01T15:05:00+00:00'),
-- (2) 11:00 / 11:12 / 11:26 / 12:10; incident 11:40 -> P3
(NEWID(), @ClmSusp, N'AppOnline',          '2026-09-28T11:00:00+00:00'),
(NEWID(), @ClmSusp, N'RideAccepted',       '2026-09-28T11:12:00+00:00'),
(NEWID(), @ClmSusp, N'PassengerPickedUp',  '2026-09-28T11:26:00+00:00'),
(NEWID(), @ClmSusp, N'RideCompleted',      '2026-09-28T12:10:00+00:00'),
-- (3) 17:45 / 18:00 / 18:09 / 18:40; incident 18:01 -> P2, boundary-flagged
(NEWID(), @ClmFlag, N'AppOnline',          '2026-10-03T17:45:00+00:00'),
(NEWID(), @ClmFlag, N'RideAccepted',       '2026-10-03T18:00:00+00:00'),
(NEWID(), @ClmFlag, N'PassengerPickedUp',  '2026-10-03T18:09:00+00:00'),
(NEWID(), @ClmFlag, N'RideCompleted',      '2026-10-03T18:40:00+00:00'),
-- (4) 07:30 / 08:00 / 08:15 / 09:00; incident 08:05 -> P2
(NEWID(), @ClmTier, N'AppOnline',          '2026-10-02T07:30:00+00:00'),
(NEWID(), @ClmTier, N'RideAccepted',       '2026-10-02T08:00:00+00:00'),
(NEWID(), @ClmTier, N'PassengerPickedUp',  '2026-10-02T08:15:00+00:00'),
(NEWID(), @ClmTier, N'RideCompleted',      '2026-10-02T09:00:00+00:00'),
-- (5) 07:00 / 07:45 / 07:55 / 08:40; incident 07:20 -> P1
(NEWID(), @ClmMed,  N'AppOnline',          '2026-10-04T07:00:00+00:00'),
(NEWID(), @ClmMed,  N'RideAccepted',       '2026-10-04T07:45:00+00:00'),
(NEWID(), @ClmMed,  N'PassengerPickedUp',  '2026-10-04T07:55:00+00:00'),
(NEWID(), @ClmMed,  N'RideCompleted',      '2026-10-04T08:40:00+00:00');

-- ---------------------------------------------  FIELD VERIFICATIONS (4x2)  --
INSERT INTO FieldVerifications (Id, ClaimId, FieldName, Status, Note) VALUES
(NEWID(), @ClmPaid, N'DriverInfo',    N'Verified', N'DL verified against Parivahan; matches policy fleet driver roster.'),
(NEWID(), @ClmPaid, N'PassengerInfo', N'Verified', N'Passenger statement consistent with trip log.'),
(NEWID(), @ClmPaid, N'TripEventLog',  N'Verified', N'Timestamps plausible; P3 confirmed.'),
(NEWID(), @ClmPaid, N'Documents',     N'Verified', N'FIR copy and garage estimate on file.'),
(NEWID(), @ClmSusp, N'DriverInfo',    N'Verified', N'DL valid.'),
(NEWID(), @ClmSusp, N'PassengerInfo', N'Verified', N'Confirmed pickup.'),
(NEWID(), @ClmSusp, N'TripEventLog',  N'Verified', N'Sequence plausible.'),
(NEWID(), @ClmSusp, N'Documents',     N'Suspicious', N'Drive link denied access on first try; photos look re-compressed — flagging for record.');

-- -------------------------------------------------------  SURVEYOR REPORTS --
INSERT INTO SurveyorReports (Id, ClaimId, OverallOutcome, Recommendation, RecommendedAmountInr, Notes, SubmittedAtUtc) VALUES
(NEWID(), @ClmPaid, N'Genuine', N'Approve', 561600.00,
 N'Site inspected 02-Oct at Sai Ram Motors, Kondapur. Repair estimate Rs 5.9L; negotiated depreciation and prior-scratch deduction to Rs 5,61,600. Recommend approval.', '2026-10-03T10:00:00+00:00'),
(NEWID(), @ClmSusp, N'Genuine', N'Approve', 480000.00,
 N'Claim genuine overall; damage pattern consistent with report. (Negative signal — suspicious fields: Documents.) Recommend approval at claimed amount.', '2026-10-03T15:00:00+00:00');

-- --------------------------------------------------------  STATUS HISTORY  --
INSERT INTO ClaimStatusHistories (Id, ClaimId, FromStatus, ToStatus, ChangedAtUtc, ChangedByUserId) VALUES
-- (1) full trail to Paid (decision lands in the dashboard month)
(NEWID(), @ClmPaid, NULL,                        N'Submitted',                '2026-10-01T16:00:00+00:00', @UserA),
(NEWID(), @ClmPaid, N'Submitted',                N'AwaitingSurveyorPickup',   '2026-10-01T16:00:00+00:00', @UserA),
(NEWID(), @ClmPaid, N'AwaitingSurveyorPickup',   N'UnderInvestigation',       '2026-10-02T09:00:00+00:00', @Surveyor),
(NEWID(), @ClmPaid, N'UnderInvestigation',       N'SurveyorReportSubmitted',  '2026-10-03T10:00:00+00:00', @Surveyor),
(NEWID(), @ClmPaid, N'SurveyorReportSubmitted',  N'Paid',                     '2026-10-04T11:00:00+00:00', @UserA),
-- (2) to SurveyorReportSubmitted — the admin's work queue
(NEWID(), @ClmSusp, NULL,                        N'Submitted',                '2026-10-02T08:00:00+00:00', @UserA),
(NEWID(), @ClmSusp, N'Submitted',                N'AwaitingSurveyorPickup',   '2026-10-02T08:00:00+00:00', @UserA),
(NEWID(), @ClmSusp, N'AwaitingSurveyorPickup',   N'UnderInvestigation',       '2026-10-02T11:00:00+00:00', @Surveyor),
(NEWID(), @ClmSusp, N'UnderInvestigation',       N'SurveyorReportSubmitted',  '2026-10-03T15:00:00+00:00', @Surveyor),
-- (3)(4)(5) intake pair only (Submitted -> AwaitingSurveyorPickup in one request)
(NEWID(), @ClmFlag, NULL, N'Submitted', '2026-10-03T19:00:00+00:00', @UserA),
(NEWID(), @ClmFlag, N'Submitted', N'AwaitingSurveyorPickup', '2026-10-03T19:00:00+00:00', @UserA),
(NEWID(), @ClmTier, NULL, N'Submitted', '2026-10-02T12:00:00+00:00', @UserB),
(NEWID(), @ClmTier, N'Submitted', N'AwaitingSurveyorPickup', '2026-10-02T12:00:00+00:00', @UserB),
(NEWID(), @ClmMed,  NULL, N'Submitted', '2026-10-04T09:30:00+00:00', @UserB),
(NEWID(), @ClmMed,  N'Submitted', N'AwaitingSurveyorPickup', '2026-10-04T09:30:00+00:00', @UserB);

PRINT 'SEED DONE — 2 companies, 3 quotes, 2 policies, 5 claims (+children) loaded.';
