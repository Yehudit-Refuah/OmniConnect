/* =====================================================================
   OmniConnect: Day-Prior Appointment Confirmation List
   ---------------------------------------------------------------------
   Purpose : List of appointments to contact in the day-prior confirmation
             run (about 9:00 AM the day before the appointment).
   Source  : eClinicalWorks (eCW) database
   Dialect : Microsoft SQL Server (T-SQL), run in SSMS
             Needs SQL Server 2017+ for CONCAT_WS (check query 1 in
             01_schema_discovery.sql: ProductVersion 14.x or higher).
   Version : DRAFT v0.2 (converted from MySQL to T-SQL). NOT yet run against eCW.

   Output  : ONE ROW PER APPOINTMENT. Grouping is done in the application:
               * same patient, same day, provider + resource  -> one call
               * family members, same day                     -> one call/text
             Each row keeps its own appointment_id so that every appointment
             gets its own status write-back (CONFPHONE, CANCSMS, ...).

   Legend  : -- VERIFY  table/column name assumed from the common eCW schema
             -- TBD     value/rule that Refuah must supply (see PLAN.md, missing info)

   Requirement rules covered here:
     [R1] Tomorrow's appointments (through the next run day, skipping Shabbat/holidays)
     [R2] eCW status = PENDING only
     [R3] Locations: Main, Twin, Hillcrest/Route 59, Wilson
     [R4] All primary care + specialty, EXCEPT Dental, Optical, WH
     [R5] Message fields: patient name, provider, time, site + address, visit type
     [R6] Flags: new patient, Spanish, late-patient alert, high-priority (no-show notice)
     [R7] Routing group: Primary Care (x1100) / Specialty (x1301) / Hillcrest (x7724) / Wilson (x1160)
     [R8] Family grouping key
   ===================================================================== */
drop table if exists #step1
-- eCW tables are read through the linked server: [ECWNODEAG01].[mobiledoc].[dbo].<table>

-- Read without taking locks, so the extract never blocks eCW users.
-- Trade-off: may see a change that is mid-save. Acceptable because the app
-- re-checks each appointment's status right before every call/text.
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;


/* ---------- Parameters ---------- */
/* [R1] Target range, with the Shabbat/holiday no-contact rule (PLAN.md "No-contact rule").
   Each run covers appointments from TOMORROW up to and including the NEXT RUN DAY,
   so the last allowed morning before a blocked stretch covers all of it.
     * A run day is any day not blocked all day: not Saturday, and no
       whole-day row in dbo.omni_no_contact_days (03_no_contact_calendar.sql).
       Fridays and holiday eves ARE run days (calls allowed until 12:00 PM).
     * Normal day:       Mon run -> Tue only
     * Friday:           Fri run -> Sat + Sun  (next run day = Sunday)
     * Before a holiday: the eve's run covers the holiday days + the day after
   Weekday from a fixed Monday (1900-01-01), so SET DATEFIRST doesn't matter: 5 = Saturday. */
DECLARE @today          date        = CAST(GETDATE() AS date);
DECLARE @target_date    date        = DATEADD(DAY, 1, @today);                   -- [R1] tomorrow
DECLARE @next_run_day   date        = @target_date;

WHILE DATEDIFF(DAY, '19000101', @next_run_day) % 7 = 5                           -- Saturday
   OR EXISTS (SELECT 1 FROM dbo.omni_no_contact_days ncd                         -- whole-day holiday
              WHERE ncd.no_contact_date = @next_run_day AND ncd.blocked_from IS NULL)
BEGIN
    SET @next_run_day = DATEADD(DAY, 1, @next_run_day);
    IF @next_run_day > DATEADD(DAY, 14, @today) BREAK;                           -- safety stop for bad calendar data
END;

DECLARE @next_date      date        = DATEADD(DAY, 1, @next_run_day);            -- end of range (exclusive)

-- Today is blocked all day (Shabbat/holiday): the job should not run. Return no rows.
IF DATEDIFF(DAY, '19000101', @today) % 7 = 5
   OR EXISTS (SELECT 1 FROM dbo.omni_no_contact_days ncd
              WHERE ncd.no_contact_date = @today AND ncd.blocked_from IS NULL)
    SET @next_date = @target_date;                                               -- empty range

DECLARE @status_pending varchar(20) = 'PEN';     -- [R2] TBD: exact eCW code for PENDING


/* ---------- Supported sites [R3] ----------
   Facility IDs, names and addresses supplied by Refuah (see PLAN.md, "Facilities").
   The INNER JOIN to this list is also the location filter: appointments at
   any other facility are dropped.
   ZIP+4 is normalised to 12345-6789. site_address is the read-out text. */
;WITH sites (facility_id, site_name, site_address, routing_site) AS (
    SELECT * FROM (VALUES
        (10, 'Refuah Health Center',   '728 North Main St., Spring Valley, NY 10977-8916', NULL),
        (22, 'Refuah Health Twin',     '5 Twin Ave, Spring Valley, NY 10977-3950',         NULL),
        (41, 'Refuah Health Route 59', '142 Route 59, Monsey, NY 10952-3406',              'HILLCREST'),  -- x7724. VERIFY: Route 59 = "Hillcrest" site
        (47, 'Wilson',                 '408 Wilson Ave, New Square, NY 10977-8916',        'WILSON')      -- x1160. VERIFY ZIP+4: same as Main
    ) v (facility_id, site_name, site_address, routing_site)
)
SELECT
    /* ===== Appointment ===== */
    e.encounterID         ,                
    e.[date]                              AS appointment_date,
    e.startTime                           AS appointment_time,     -- VERIFY type (time vs varchar 'HH:MM AM')
    e.STATUS                              AS ecw_status,           -- PENDING at extract time; re-checked before each call
    e.VisitType                           AS visit_type_code,
    vc.Description                        AS visit_type_desc,      -- [R5] read out unless patient is new (rule applied in app)
    e.reason                              AS appt_reason,          -- VERIFY; may not be needed
    e.generalNotes                        AS appt_notes,           -- VERIFY; may hold "new patient: arrive early" note [R6] TBD
    
    /* ===== Patient ===== */
    e.patientID                           AS patient_id,
    p.ControlNo                           AS mrn,                  -- VERIFY: MRN / account no. column (dashboard search)
    pu.ufname                             AS patient_first_name,   -- [R5]
    pu.ulname                             AS patient_last_name,    -- [R5]
    pu.dob                                AS patient_dob,          -- used for callback identity verification
    -- Exact age on the appointment date. TRY_CONVERT in case dob is stored as text.  VERIFY dob type
    DATEDIFF(YEAR, TRY_CONVERT(date, pu.dob), e.[date])
      - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, TRY_CONVERT(date, pu.dob), e.[date]),
                          TRY_CONVERT(date, pu.dob)) > CAST(e.[date] AS date)
             THEN 1 ELSE 0 END            AS patient_age,          -- TBD: is Peds vs Adult by age or by department?

    /* ===== Phones (all on file; multi-contact is Phase 2) ===== */
    pu.upPhone                            AS phone_home,           -- VERIFY
    pu.umobileno                          AS phone_mobile,         -- VERIFY; preferred for SMS
    -- p.workPhone                           AS phone_work,           -- VERIFY / TBD: column may not exist
    -- TBD: additional contact numbers (other table?) for Phase 2 multi-contact
    pu.uemail                             AS patient_email,        -- VERIFY; for future email channel

    /* ===== Language ===== */
    p.language                            AS language_raw,         -- VERIFY column
    CASE
        WHEN p.language LIKE 'Span%' THEN 1                        -- TBD: exact value
        -- TBD: OR patient has a "Spanish" alert (if stored as an alert, not the language field)
        ELSE 0
    END                                   AS is_spanish,           -- [R6]

    /* ===== Provider & resource ===== */
    e.doctorID                            AS provider_id,
    CONCAT_WS(' ', du.ufname, du.ulname)  AS provider_name,        -- [R5] TBD: read-out format ("Dr. Smith"?)
    d.speciality                          AS provider_specialty,   -- VERIFY spelling
    e.ResourceId                          AS resource_id,          -- VERIFY; same-day provider + resource -> one call
    CONCAT_WS(' ', ru.ufname, ru.ulname)  AS resource_name,        -- VERIFY: are resources stored in users?

    /* ===== Site ===== */
    e.facilityId                          AS facility_id,
    s.site_name                           AS site_name,            -- [R5]
    s.site_address                        AS site_address,         -- [R5] TBD: read-out format (speak ZIP+4?)

    /* ===== Derived flags ===== */

    -- [R6] New patient: globalalertdetails alert 95 or 117 (supplied by Refuah). See the "al" APPLY below.
    al.is_new_patient                     AS is_new_patient,

    -- [R6] Late-patient alert: arrive 10 min early (Peds) or 15 min early (Adults/Family).
    -- Source: globalalertdetails, alert codes 6 and 79 = late patient (supplied by Refuah). See the "al" APPLY below.
    al.has_late_alert                     AS has_late_alert,

    -- [R6] High-priority visits: no-show notice on voicemail + at-risk alerts on the dashboard
    CASE
        WHEN al.is_new_patient = 1                                 -- New Patient (alert 95/117)
          OR e.VisitType like '%well%'                          -- TBD: Adult Well Visit codes
          OR e.VisitType like '%CONS%'                              -- TBD: Specialty Consult codes
        THEN 1 ELSE 0
    END                                   AS is_high_priority,

    -- [R7] Routing group for reschedule transfers.
    -- Assumption: SITE takes priority over department (Hillcrest/Wilson have their own lines).  TBD: confirm
    CASE
        WHEN s.routing_site IS NOT NULL                            THEN s.routing_site  -- 41 HILLCREST x7724, 47 WILSON x1160
        WHEN d.speciality IN ('Internal Medicine', 'Family Medicine',
                              'Pediatrics', 'Adult Medicine')       -- TBD: real primary care specialty values
                                                                   THEN 'PRIMARY_CARE' -- x1100
        ELSE 'SPECIALTY'                                                                -- x1301
    END                                   AS routing_group,

    -- Peds vs Adult/Family (drives the 10 vs 15 minute late-arrival rule)
    CASE
        WHEN d.speciality = 'Pediatrics' THEN 'PEDS'               -- TBD: by department or by age?
        ELSE 'ADULT_FAMILY'
    END                                   AS care_group,

    -- [R8] Family grouping key. TBD: guarantor? household? shared phone?
    -- Placeholder: guarantor ID if it exists, otherwise the mobile/home phone.
    COALESCE(
        CAST(p.GrId AS varchar(50)),                               -- VERIFY / TBD: guarantor column
        NULLIF(pu.umobileno, ''),
        pu.upPhone
    )                                     AS family_group_key
    into #step1
FROM [ECWNODEAG01].[mobiledoc].[dbo].enc e
    JOIN [ECWNODEAG01].[mobiledoc].[dbo].patients p             ON p.pid      = e.patientID   -- join columns
    JOIN [ECWNODEAG01].[mobiledoc].[dbo].users pu               ON pu.uid     = e.patientID   -- patient demographics
    LEFT JOIN [ECWNODEAG01].[mobiledoc].[dbo].doctors d         ON d.doctorID = e.doctorID
    LEFT JOIN [ECWNODEAG01].[mobiledoc].[dbo].users du          ON du.uid     = e.doctorID    -- provider name
    LEFT JOIN [ECWNODEAG01].[mobiledoc].[dbo].users ru          ON ru.uid     = e.ResourceId  -- resource name
    JOIN sites s                    ON s.facility_id = e.facilityId   -- supported sites only
    LEFT JOIN [ECWNODEAG01].[mobiledoc].[dbo].visitcodes vc     ON vc.Name    = e.VisitType   -- VERIFY join column
    left join dbo.vw_TestPatients tp on tp.patientId = e.patientid
        CROSS APPLY (
        SELECT ISNULL(MAX(CASE WHEN ga.AlertId IN (6, 79)   THEN 1 END), 0) AS has_late_alert,
               ISNULL(MAX(CASE WHEN ga.AlertId IN (95, 117) THEN 1 END), 0) AS is_new_patient
        FROM [ECWNODEAG01].[mobiledoc].[dbo].globalalertdetails ga
        WHERE ga.patientId = e.patientID                            
          AND ga.AlertId IN (6, 79, 95, 117)
          AND ga.deleteFlag = 0                                     
        
    ) al

WHERE
    /* [R1] tomorrow. Half-open range works whether enc.date is date or datetime,
       and still uses an index on enc.date. */
    e.[date] >= @target_date
    AND e.[date] <  @next_date

    /* [R2] PENDING only */
    AND e.STATUS = @status_pending

    /* appointments only, not deleted */
    AND e.deleteFlag = 0                                           -- VERIFY
    -- AND e.encType = 1                                           -- TBD: filter to real appointments (not phone encounters, labs, etc.)

    /* [R3] supported locations: enforced by the JOIN to sites (10, 22, 41, 47) */

    /* [R4] exclude Dental, Optical, Women's Health */
    AND COALESCE(d.speciality, '') NOT IN ('Dental', 'Dentistry','Maternal Fetal Medicine',
                                           'Optical', 'Optometry',
                                           'OB/GYN', 'Women''s Health','Obstetrics and Gynecology')   -- TBD: real values, and is this
                                                                          --      decided by specialty, facility,
                                                                          --      department or visit type?

    /* data quality exclusions. TBD: confirm each with Refuah */
    AND pu.delFlag = 0                                             -- VERIFY: inactive/deleted patient
    -- AND p.deceased = 0                                          -- TBD: deceased flag column
    -- AND pu.ulname NOT LIKE 'TEST%'                              -- TBD: how are test patients marked?
    -- AND <telehealth visit types excluded?>                      -- TBD
    -- AND <SMS/call opt-out check>                                -- TBD: where is consent stored?
;


/* ---------- Final output: arrival-time adjustment [R6] ----------
   arrival_offset_minutes = minutes to ADD to the appointment time to get the
   time the patient is told to arrive (negative = earlier).
     * Late-patient alert, Pediatrics       -> -10
     * Late-patient alert, Adults/Family    -> -15
     * Otherwise                            ->   0
   TBD: new patients with an "arrive earlier" note. The rule is to remind them
        of the adjusted time written in the note, but where the note lives and
        how the time is written is still unknown (PLAN.md item 16). Until then
        they get 0 here, and appt_notes is passed through for the app. */
SELECT s1.family_group_key,patient_id,
    s1.*,
    adj.arrival_offset_minutes,
    -- Time the patient is told to arrive. NULL if appointment_time can't be read as a time.
    DATEADD(MINUTE, adj.arrival_offset_minutes,
            TRY_CONVERT(time, s1.appointment_time)) AS arrival_time,  -- VERIFY: startTime format

    -- [R8] Family visit: 2+ DIFFERENT patients with the same family_group_key on the same day
    --      -> one combined call/text. (One patient with several appointments is NOT a family visit.)
    ISNULL(fam.family_member_count, 1)              AS family_member_count,
    CASE WHEN fam.family_member_count >= 2 THEN 1 ELSE 0 END AS is_family_visit
FROM #step1 s1
CROSS APPLY (
    SELECT CASE
               WHEN s1.has_late_alert = 1 AND s1.care_group = 'PEDS' THEN -10
               WHEN s1.has_late_alert = 1                            THEN -15   -- ADULT_FAMILY
               ELSE 0
           END AS arrival_offset_minutes
) adj
-- Distinct patients per family per day. A NULL family_group_key (no guarantor and
-- no phone) never matches, so that patient is treated as a family of 1.
LEFT JOIN (
    SELECT family_group_key, appointment_date,
           COUNT(DISTINCT patient_id) AS family_member_count
    FROM #step1
    WHERE family_group_key IS NOT NULL
    GROUP BY family_group_key, appointment_date
) fam
    ON  fam.family_group_key = s1.family_group_key
    AND fam.appointment_date = s1.appointment_date

-- Uncomment to list ONLY family visits:
-- WHERE fam.family_member_count >= 2
-- ORDER BY on the final SELECT (an ORDER BY on SELECT ... INTO is not kept)
ORDER BY
    s1.family_group_key,
    s1.patient_id,
    TRY_CONVERT(time, s1.appointment_time);
/* =====================================================================
   NOTES FOR REVIEW
   1. This query is READ-ONLY. Status write-back (CONFPHONE, CANCSMS, ...)
      must go through a supported eCW interface (API / HL7). TBD.
   2. Before each call or text, the app re-checks that one appointment's
      current status (requirement: "use the most up-to-date status").
      Query: 04_visit_status_now.sql. Used at the PBX "dialing" step (TODO B6.2).
   3. Rows with no usable phone number are still returned. The app marks
      them FAILEDMSG and shows them on the dashboard instead of silently
      dropping them.
   4. Same-day reminder = this query with the status filter removed and
      @target_date = CAST(GETDATE() AS date). A separate file will follow after review.
   5. Later, this query becomes a view or stored procedure in a separate
      read-only schema/database, so OmniConnect never needs rights on eCW tables.  TBD with DBA
   ===================================================================== */
