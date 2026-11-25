/* =====================================================================
   OmniConnect: Visit status right before dialing
   ---------------------------------------------------------------------
   Purpose : The last check before the phone rings. For the appointments on
             one call, return how each looks in eCW RIGHT NOW, so the app can
             skip visits that were cancelled, confirmed, moved or deleted
             since the morning list (02_day_prior_confirmation_list.sql).
   Used by : backend/app/rules/eligibility.py, current_visits() (from TODO B7 on)
   Dialect : Microsoft SQL Server (T-SQL)
   Version : DRAFT v0.1. NOT yet run against eCW.

   Notes   :
     * No READ UNCOMMITTED here (unlike the morning list): this check must
       see only saved changes, never a change that is still mid-save.
     * The app sends the appointment IDs as parameters (one ? per ID),
       never pasted into the text.
     * Rules applied in the app, not here, so a missing row also counts:
         still due = row found AND STATUS = PENDING AND deleteFlag = 0
                     AND date + startTime = the time we would read out
     * If this query fails or times out, the app does NOT dial
       (reason "status_check_failed").
   ===================================================================== */

SELECT
    e.encounterID   AS appointment_id,
    e.STATUS        AS ecw_status,     -- TBD: exact PENDING code, same as @status_pending in 02_...sql
    e.[date]        AS appointment_date,
    e.startTime     AS appointment_time,  -- VERIFY type (time vs varchar 'HH:MM AM'), same as 02_...sql
    e.deleteFlag    AS deleted         -- VERIFY
FROM [ECWNODEAG01].[mobiledoc].[dbo].enc e
WHERE e.encounterID IN (?);            -- the app expands this to (?, ?, ...) for the call's appointments
