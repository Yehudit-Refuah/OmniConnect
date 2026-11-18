/* =====================================================================
   OmniConnect: eCW Schema Discovery
   Purpose : Answer the "missing info" items in PLAN.md (section B and part of C).
   Safety  : READ-ONLY. Returns structure and code lists, NOT patient data.
   Dialect : Microsoft SQL Server (T-SQL), run in SSMS
   Run on  : reporting replica / readable secondary if available.
   Tables  : eCW tables are read through the linked server, using four-part
             names: [ECWNODEAG01].[mobiledoc].[dbo].<table>
   How     : Run one section at a time; each SELECT gives its own result grid.
   ===================================================================== */

-- Read without blocking eCW users (no locks held). Fine for discovery counts.
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;


/* ---------- 1. Which server/database are we in? ---------- */
-- Runs ON the linked server (local DB_NAME()/@@VERSION would describe the local server).
-- Needs the linked server's "RPC Out" option enabled.  VERIFY
-- Alternative if RPC Out is off:
--   SELECT * FROM OPENQUERY([ECWNODEAG01], 'SELECT @@SERVERNAME AS server_name, @@VERSION AS full_version');
-- The version that matters for CONCAT_WS is the LOCAL server's (the query is compiled
-- locally), so run the local check too.
EXEC ('SELECT DB_NAME()                        AS current_db,
              @@SERVERNAME                     AS server_name,
              SERVERPROPERTY(''ProductVersion'') AS product_version,
              SERVERPROPERTY(''Edition'')        AS edition,
              @@VERSION                        AS full_version') AT [ECWNODEAG01];

SELECT @@SERVERNAME                            AS local_server_name,
       SERVERPROPERTY('ProductVersion')        AS local_product_version;   -- 14.x = SQL 2017, 15.x = 2019, 16.x = 2022


/* ---------- 2. Column lists of the core tables ---------- */
-- Confirms the column names used in 02_day_prior_confirmation_list.sql.
-- enc = appointments/encounters, patients = MRN/language/guarantor,
-- users = names/DOB/address/phones (patients AND providers),
-- doctors = providers/resources + specialty, edi_facilities = sites,
-- visitcodes = visit type codes.
SELECT c.TABLE_SCHEMA, c.TABLE_NAME, c.ORDINAL_POSITION, c.COLUMN_NAME,
       c.DATA_TYPE, c.CHARACTER_MAXIMUM_LENGTH, c.IS_NULLABLE
FROM [ECWNODEAG01].[mobiledoc].INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_NAME IN ('enc', 'patients', 'users', 'doctors',
                       'edi_facilities', 'visitcodes')
ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION;

-- If any of the 6 tables is missing above, find the real name:
SELECT t.TABLE_SCHEMA, t.TABLE_NAME, t.TABLE_TYPE
FROM [ECWNODEAG01].[mobiledoc].INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_NAME LIKE '%enc%' OR t.TABLE_NAME LIKE '%patient%'
   OR t.TABLE_NAME LIKE '%facilit%' OR t.TABLE_NAME LIKE '%visitcode%'
   OR t.TABLE_NAME LIKE '%doctor%'
ORDER BY t.TABLE_NAME;


/* ---------- 3. Appointment status codes in use (finds the PENDING code) ---------- */
SELECT e.STATUS, COUNT(*) AS appt_count
FROM [ECWNODEAG01].[mobiledoc].[dbo].enc e
WHERE e.[date] >= DATEADD(DAY, -30, CAST(GETDATE() AS date))
  AND e.[date] <  DATEADD(DAY,  31, CAST(GETDATE() AS date))
GROUP BY e.STATUS
ORDER BY appt_count DESC;

-- Are the OmniConnect status codes already configured in eCW?
-- (CONFPHONE, CONFSMS, CANCPHONE, CANCSMS, MSNGRVCMSG, FAILEDMSG, MANSNOACTN)
-- TBD: find the table that holds the status master list. Search for it:
SELECT t.TABLE_SCHEMA, t.TABLE_NAME
FROM [ECWNODEAG01].[mobiledoc].INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_NAME LIKE '%status%' OR t.TABLE_NAME LIKE '%visitst%'
ORDER BY t.TABLE_NAME;


/* ---------- 4. Visit types in use (finds New Patient / Well / Consult codes) ---------- */
SELECT e.VisitType, vc.Description, COUNT(*) AS appt_count
FROM [ECWNODEAG01].[mobiledoc].[dbo].enc e
LEFT JOIN [ECWNODEAG01].[mobiledoc].[dbo].visitcodes vc ON vc.Name = e.VisitType        -- VERIFY join column
WHERE e.[date] >= DATEADD(DAY, -90, CAST(GETDATE() AS date))
  AND e.[date] <  DATEADD(DAY,  31, CAST(GETDATE() AS date))
GROUP BY e.VisitType, vc.Description
ORDER BY appt_count DESC;


/* ---------- 5. Facilities: confirm the 4 supported sites ---------- */
-- IDs are known (see PLAN.md, "Facilities"): 10 Main, 22 Twin, 41 Route 59/Hillcrest, 47 Wilson.
-- Use this to check that eCW's stored names/addresses match the hard-coded
-- list in 02_day_prior_confirmation_list.sql.
SELECT f.Id, f.Name, f.AddressLine1, f.AddressLine2, f.City, f.State, f.Zip   -- VERIFY columns
FROM [ECWNODEAG01].[mobiledoc].[dbo].edi_facilities f
WHERE f.Id IN (10, 22, 41, 47)
ORDER BY f.Id;

-- Upcoming appointments at sites NOT in the list (checks that no in-scope site is missing)
SELECT e.facilityId, f.Name, COUNT(*) AS appt_count
FROM [ECWNODEAG01].[mobiledoc].[dbo].enc e
LEFT JOIN [ECWNODEAG01].[mobiledoc].[dbo].edi_facilities f ON f.Id = e.facilityId
WHERE e.[date] >= CAST(GETDATE() AS date)
  AND e.[date] <  DATEADD(DAY, 15, CAST(GETDATE() AS date))
  AND e.facilityId NOT IN (10, 22, 41, 47)
GROUP BY e.facilityId, f.Name
ORDER BY appt_count DESC;


/* ---------- 6. Provider specialties (finds Dental / Optical / WH / Peds / Specialty) ---------- */
SELECT d.speciality, COUNT(*) AS provider_count          -- VERIFY spelling: speciality vs specialty
FROM [ECWNODEAG01].[mobiledoc].[dbo].doctors d
GROUP BY d.speciality
ORDER BY d.speciality;

-- Specialty broken down by facility, using actual upcoming appointments
SELECT f.Name AS facility, d.speciality, COUNT(*) AS appt_count
FROM [ECWNODEAG01].[mobiledoc].[dbo].enc e
JOIN [ECWNODEAG01].[mobiledoc].[dbo].doctors d              ON d.doctorID = e.doctorID
LEFT JOIN [ECWNODEAG01].[mobiledoc].[dbo].edi_facilities f  ON f.Id       = e.facilityId
WHERE e.[date] >= CAST(GETDATE() AS date)
  AND e.[date] <  DATEADD(DAY, 15, CAST(GETDATE() AS date))
GROUP BY f.Name, d.speciality
ORDER BY f.Name, appt_count DESC;


/* ---------- 7a. Patient alerts: globalalertdetails (late patient = 6, 79; new patient = 95, 117) ---------- */
-- Column list, to confirm the patient / alert-code / delete-flag / expiry column names
-- used for has_late_alert in 02_day_prior_confirmation_list.sql.
SELECT c.ORDINAL_POSITION, c.COLUMN_NAME, c.DATA_TYPE, c.IS_NULLABLE
FROM [ECWNODEAG01].[mobiledoc].INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = 'dbo' AND c.TABLE_NAME = 'globalalertdetails'
ORDER BY c.ORDINAL_POSITION;

-- Alert codes in use, with counts only (no PHI). Confirms 6 and 79, and may show
-- a Spanish-language alert code too.
SELECT ga.alertId, COUNT(*) AS alert_count, COUNT(DISTINCT ga.patientId) AS patient_count   -- VERIFY columns
FROM [ECWNODEAG01].[mobiledoc].[dbo].globalalertdetails ga
GROUP BY ga.alertId
ORDER BY ga.alertId;


/* ---------- 7. Find where alerts, language, guarantor, consent and phones live ---------- */
-- Tables whose names suggest alerts / notes / consent
SELECT t.TABLE_SCHEMA, t.TABLE_NAME
FROM [ECWNODEAG01].[mobiledoc].INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_NAME LIKE '%alert%'   OR t.TABLE_NAME LIKE '%consent%'
   OR t.TABLE_NAME LIKE '%optout%'  OR t.TABLE_NAME LIKE '%contact%'
   OR t.TABLE_NAME LIKE '%resource%' OR t.TABLE_NAME LIKE '%department%'
ORDER BY t.TABLE_NAME;

-- Columns whose names suggest language / guarantor / phones / consent / deceased
SELECT c.TABLE_NAME, c.COLUMN_NAME, c.DATA_TYPE
FROM [ECWNODEAG01].[mobiledoc].INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_NAME IN ('enc', 'patients', 'users', 'doctors')
  AND (c.COLUMN_NAME LIKE '%lang%'    OR c.COLUMN_NAME LIKE '%guar%'
    OR c.COLUMN_NAME LIKE '%gr%id%'   OR c.COLUMN_NAME LIKE '%phone%'
    OR c.COLUMN_NAME LIKE '%mobile%'  OR c.COLUMN_NAME LIKE '%sms%'
    OR c.COLUMN_NAME LIKE '%text%'    OR c.COLUMN_NAME LIKE '%consent%'
    OR c.COLUMN_NAME LIKE '%decease%' OR c.COLUMN_NAME LIKE '%status%'
    OR c.COLUMN_NAME LIKE '%resource%' OR c.COLUMN_NAME LIKE '%dept%'
    OR c.COLUMN_NAME LIKE '%note%')
ORDER BY c.TABLE_NAME, c.COLUMN_NAME;

-- Language values in use (only counts, no PHI)
-- VERIFY: column name, depending on the result of the query above
SELECT p.language, COUNT(*) AS patient_count
FROM [ECWNODEAG01].[mobiledoc].[dbo].patients p
GROUP BY p.language
ORDER BY patient_count DESC;


/* ---------- 8. Date / start-time format check (5 rows, times only, no PHI) ---------- */
SELECT TOP (5) e.[date], e.startTime, e.endTime,
       SQL_VARIANT_PROPERTY(e.[date], 'BaseType')    AS date_type,
       SQL_VARIANT_PROPERTY(e.startTime, 'BaseType') AS starttime_type
FROM [ECWNODEAG01].[mobiledoc].[dbo].enc e
WHERE e.[date] >= CAST(GETDATE() AS date)
  AND e.[date] <  DATEADD(DAY, 1, CAST(GETDATE() AS date));


/* ---------- 9. Index check on enc (performance) ---------- */
-- OBJECT_ID() only resolves local objects, so join to the remote sys.tables/sys.schemas instead.
SELECT i.name AS index_name, i.type_desc, i.is_unique,
       ic.key_ordinal, col.name AS column_name, ic.is_included_column
FROM [ECWNODEAG01].[mobiledoc].sys.indexes i
JOIN [ECWNODEAG01].[mobiledoc].sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN [ECWNODEAG01].[mobiledoc].sys.columns col      ON col.object_id = ic.object_id AND col.column_id = ic.column_id
JOIN [ECWNODEAG01].[mobiledoc].sys.tables tb        ON tb.object_id  = i.object_id
JOIN [ECWNODEAG01].[mobiledoc].sys.schemas sc       ON sc.schema_id  = tb.schema_id
WHERE sc.name = 'dbo' AND tb.name = 'enc'
ORDER BY i.name, ic.is_included_column, ic.key_ordinal;
