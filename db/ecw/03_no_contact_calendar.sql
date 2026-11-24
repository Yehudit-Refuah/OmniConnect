/* =====================================================================
   OmniConnect: No-Contact Calendar (Shabbat & Jewish holidays)
   ---------------------------------------------------------------------
   Rule (agreed with Refuah 2026-11-09, see PLAN.md "No-contact rule"):
     No calls or texts from 12:00 PM on a Friday or holiday eve
     until the morning of the next regular day.

   Fridays and Saturdays are built into the logic (day-prior query and the
   calling app), so this table only needs JEWISH HOLIDAY dates:
     * eve of a holiday   -> blocked_from = '12:00'
     * holiday day        -> blocked_from = NULL (whole day)
   A row on a Friday/Saturday is allowed; the stricter rule wins.

   Lives in the LOCAL database (same one as dbo.vw_TestPatients), not in eCW.
   Filled automatically: OmniConnect's daily job (TODO B7) works out the
   holidays with the pyluach library and inserts any missing dates for the
   next 13 months. It never changes existing rows, so rows added by hand
   (e.g. clinic closures) are kept.
   Dialect : Microsoft SQL Server (T-SQL)
   ===================================================================== */

-- USE <local database>;                          -- VERIFY: same DB as dbo.vw_TestPatients

IF OBJECT_ID('dbo.omni_no_contact_days', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.omni_no_contact_days (
        no_contact_date date          NOT NULL PRIMARY KEY,
        blocked_from    time(0)       NULL,     -- NULL = whole day blocked; 12:00 = eve, blocked from noon
        reason          nvarchar(100) NOT NULL, -- e.g. 'Erev Pesach', 'Pesach I'
        clinic_closed   bit           NOT NULL CONSTRAINT DF_omni_ncd_closed DEFAULT 0,  -- info only: no appointments that day
        added_by        nvarchar(100) NOT NULL CONSTRAINT DF_omni_ncd_by     DEFAULT SUSER_SNAME(),
        added_on        datetime2(0)  NOT NULL CONSTRAINT DF_omni_ncd_on     DEFAULT SYSDATETIME()
    );
END;


/* ---------- Loading holidays (template) ----------
   One row per date. Replace the placeholders with the dates from Refuah's
   calendar. Example pattern for a two-day holiday:

INSERT INTO dbo.omni_no_contact_days (no_contact_date, blocked_from, reason, clinic_closed) VALUES
    ('YYYY-MM-DD', '12:00', N'Erev <holiday>', 0),   -- eve: calls until 12:00 PM
    ('YYYY-MM-DD', NULL,    N'<holiday> I',    1),   -- whole day
    ('YYYY-MM-DD', NULL,    N'<holiday> II',   1);   -- whole day
*/


/* ---------- Check: upcoming blocked days, including the built-in Fri/Sat rule ----------
   Weekday is computed from a fixed Monday (1900-01-01) so it doesn't depend
   on SET DATEFIRST or the server language: 0 = Mon ... 4 = Fri, 5 = Sat. */
WITH days AS (
    SELECT TOP (60) DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1,
                            CAST(GETDATE() AS date)) AS d
    FROM sys.all_objects
)
SELECT days.d                                       AS calendar_date,
       DATENAME(WEEKDAY, days.d)                    AS weekday_name,
       CASE
           WHEN DATEDIFF(DAY, '19000101', days.d) % 7 = 5
             OR (ncd.no_contact_date IS NOT NULL AND ncd.blocked_from IS NULL) THEN 'BLOCKED ALL DAY'
           ELSE 'CALLS UNTIL 12:00 PM'
       END                                          AS contact_rule,
       COALESCE(ncd.reason,
                CASE DATEDIFF(DAY, '19000101', days.d) % 7
                    WHEN 4 THEN 'Erev Shabbat' WHEN 5 THEN 'Shabbat' END) AS reason
FROM days
LEFT JOIN dbo.omni_no_contact_days ncd ON ncd.no_contact_date = days.d
WHERE DATEDIFF(DAY, '19000101', days.d) % 7 IN (4, 5)
   OR ncd.no_contact_date IS NOT NULL
ORDER BY days.d;
