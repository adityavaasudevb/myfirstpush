-- ============================================================================
--  v3.4 demo policies — TWO rows, no IDs typed by hand.
--  Run against Tnc_InsuranceDb AFTER the two company profiles exist
--  (register + complete profile first, otherwise the lookup returns NULL).
--
--  Why SQL and not the app: PolicyService FR4.4 sets StartDateUtc = UtcNow on
--  payment, so a policy created today can never cover a 15 Nov incident.
--
--  Premium must equal fleet x 15,000 x tier multiplier x (1 + sum of add-on rates)
--    SwiftFleet : 25 x 15,000 x 1.6 x 1.17 = 702,000.00   (PD 0.12 + UM 0.05)
--    Deccan     : 10 x 15,000 x 1.6 x 1.18 = 289,000.00   (PD 0.12 + MedPay 0.06)
-- ============================================================================

USE [Tnc_InsuranceDb];
GO

SET NOCOUNT ON;

DECLARE @SwiftSwift uniqueidentifier, @DeccanProfile uniqueidentifier;

SELECT @SwiftSwift = (SELECT TOP 1 Id FROM CompanyProfiles WHERE Email = N'company@swiftfleet.in');
SELECT @DeccanProfile = (SELECT TOP 1 Id FROM CompanyProfiles WHERE Email = N'fleet@deccanfleet.in');

IF @SwiftSwift IS NULL
    THROW 50001, 'No company profile for company@swiftfleet.in - register and complete the profile first.', 1;
IF @DeccanProfile IS NULL
    THROW 50002, 'No company profile for fleet@deccanfleet.in - register and complete the profile first.', 1;

-- ---------------------------------------------------------------------------
-- Policy A - SwiftFleet - 20 Sep 2026 -> 19 Sep 2027 (already active, no renewal)
-- ---------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM Policies WHERE PolicyNumber = N'POL-2026-AA0001')
    DELETE FROM Policies WHERE PolicyNumber = N'POL-2026-AA0001';   -- safe: claims reference Id, take care with live data

INSERT INTO Policies
    (Id, PolicyNumber, CompanyProfileId, OriginQuoteId, Tier, AddOns, FleetSize, PremiumInr,
     Status, StartDateUtc, EndDateUtc, CreatedAtUtc, RenewedFromPolicyId, ReviewRequired)
VALUES
    (NEWID(), N'POL-2026-AA0001', @SwiftSwift, NULL, N'Tier B',
     N'["Physical Damage","Uninsured Motorist"]', 25, 702000.00,
     N'Active', '2026-09-20T10:00:00+00:00', '2027-09-19T10:00:00+00:00',
     '2026-09-20T09:00:00+00:00', NULL, 0);

-- ---------------------------------------------------------------------------
-- Policy B - Deccan Fleet - 01 Jan 2026 -> 31 Dec 2026
-- ---------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM Policies WHERE PolicyNumber = N'POL-2026-DD0002')
    DELETE FROM Policies WHERE PolicyNumber = N'POL-2026-DD0002';

INSERT INTO Policies
    (Id, PolicyNumber, CompanyProfileId, OriginQuoteId, Tier, AddOns, FleetSize, PremiumInr,
     Status, StartDateUtc, EndDateUtc, CreatedAtUtc, RenewedFromPolicyId, ReviewRequired)
VALUES
    (NEWID(), N'POL-2026-DD0002', @DeccanProfile, NULL, N'Tier B',
     N'["Physical Damage","Medical Payments"]', 10, 289000.00,
     N'Active', '2026-01-01T10:00:00+00:00', '2026-12-31T10:00:00+00:00',
     '2026-01-01T09:00:00+00:00', NULL, 0);

SELECT PolicyNumber, Tier, PremiumInr, Status, StartDateUtc, EndDateUtc
FROM Policies
WHERE PolicyNumber IN (N'POL-2026-AA0001', N'POL-2026-DD0002');
GO
