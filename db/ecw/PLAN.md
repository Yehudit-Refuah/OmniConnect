# eCW Patient List Query: Plan & Missing Information

**Component:** Automated Appointment Confirmations & Reminders
**Goal:** Pull the list of patients to contact from eClinicalWorks (eCW) for:
1. **Day-prior confirmation:** runs about 9:00 AM, covers tomorrow's appointments, status PENDING only
2. **Same-day reminder:** 1.5 hours before each appointment, all statuses (variant built later from the same base query)

**Status:** DRAFT v0.3 (2026-11-09). T-SQL, run in SSMS against the eCW linked server `[ECWNODEAG01].[mobiledoc].[dbo]`. The day-prior query is being tested but is **not yet validated** (Step 5). The open items are listed under **Query TODO** below.

---

## Files

| File | Purpose |
|---|---|
| `PLAN.md` | This plan and the missing-info list |
| `01_schema_discovery.sql` | Read-only queries to run in eCW. Their results fill in most of the missing info |
| `02_day_prior_confirmation_list.sql` | Draft day-prior patient list query, with comments |
| `03_no_contact_calendar.sql` | Shabbat/holiday no-contact calendar table (local database) and a check query |

Comment tags used in the SQL:
- `-- VERIFY`: a table or column name assumed from the common eCW schema. Confirm it against Refuah's database.
- `-- TBD`: a value or business rule that Refuah has to supply (see the missing-info list below).

---

## Query TODO (`02_day_prior_confirmation_list.sql`)

### What the query does now
- **Step 1, `#step1`:** tomorrow's PENDING appointments at the 4 supported sites (`sites` CTE), excluding Dental, Optical and Women's Health by provider specialty, with patient, provider, site, phone and language fields.
- **Alerts:** one `CROSS APPLY` on `globalalertdetails` sets `has_late_alert` (codes 6, 79) and `is_new_patient` (codes 95, 117).
- **Final `SELECT`** adds three things:
  - `arrival_offset_minutes`: late alert = -10 for Pediatrics, -15 for Adults/Family, otherwise 0
  - `arrival_time`: the appointment time plus the offset
  - `family_member_count` and `is_family_visit`: 2+ different patients with the same `family_group_key` on the same day

### Fix in the query (no input from Refuah needed)
- [ ] **Test patients are not excluded.** `vw_TestPatients` is joined, but nothing filters on it. Add `AND tp.patientId IS NULL` to the `WHERE`.
- [ ] **Remove the debug filter** `where s1.family_group_key = '...'` from the final `SELECT`. While it's active, the query returns only that one family.
- [x] **`is_new_patient_by_history` removed** (2026-11-09). New patient now comes only from the 95/117 alert.
- [ ] **Speed over the linked server:** time a full run. If it's slow, move the eCW part into `OPENQUERY` so the filters run on the eCW server.
- [ ] **Make it a stored procedure** with `@target_date` as a parameter, ready for the sync service and the same-day variant.

### Confirm against the eCW schema (`-- VERIFY` in the SQL; run `01_schema_discovery.sql`)
- [ ] Is `enc.startTime` a time or text? This affects `arrival_time` and the sort. Check whether `TRY_CONVERT(time, ...)` returns NULL for any rows.
- [ ] `enc.deleteFlag`, `pu.delFlag`, and `dob` stored as a date or text.
- [ ] Phone and email columns: `upPhone`, `umobileno`, `uemail`. Does `workPhone` exist (currently commented out)?
- [ ] `p.ControlNo` is the MRN; `p.language` holds the language.
- [ ] `d.speciality` spelling; `visitcodes` join on `vc.Name = e.VisitType`.
- [ ] Resources: are they stored in `users`? (`e.ResourceId` joined to `users.uid`)
- [ ] `p.GrId` is the guarantor column.
- [ ] `globalalertdetails`: do alerts expire or get inactivated? If there's an end date, add it to the `CROSS APPLY` filter.

### Waiting on Refuah (`-- TBD` in the SQL)
- [ ] **PENDING status code:** `'PEN'` is a guess (item 7).
- [ ] **Exclusions by specialty:** the current list is Dental, Dentistry, Maternal Fetal Medicine, Optical, Optometry, OB/GYN, Women's Health, and Obstetrics and Gynecology. Is specialty the right basis, and is the list complete? (Items 11, 12, 25)
- [ ] **Primary Care vs Specialty routing:** the list of primary care specialty values (item 13).
- [ ] **Peds vs Adults/Family:** decided by specialty or by age? It drives the -10/-15 offset (item 14).
- [ ] **New-patient arrival note:** where the earlier time is written. New patients currently get offset 0 (item 16).
- [ ] **New-patient alert 95/117:** is it removed after the first visit? (item 15)
- [ ] **Spanish:** an alert or the language field, and the exact value? (item 18)
- [ ] **High-priority visit types:** Well Visit and Consult are `LIKE '%well%'` and `LIKE '%CONS%'` placeholders (item 19).
- [ ] **Family grouping key:** guarantor, then mobile, then home phone is a placeholder (item 20).
- [ ] **Real appointments only:** `encType` filter to drop phone encounters, labs, etc. (item 25)
- [ ] **Other exclusions:** deceased patients, telehealth, SMS/call opt-out (items 23, 24).
- [ ] **Weekend/holiday rule** for the target date (item 26).
- [ ] **Read-out formats:** provider name ("Dr. Smith"?) and address (speak the ZIP+4?) (item 22).
- [ ] **Facilities:** is Route 59 the "Hillcrest" site, and is Wilson's ZIP+4 correct? (item 21)

---

## No-contact rule (Shabbat & Jewish holidays)

Agreed with Refuah on 2026-11-09: **no calls or texts from 12:00 PM on a Friday or holiday eve until the morning of the next regular day.**

| Day type | Contact allowed |
|---|---|
| Regular day | Normal hours |
| Friday / eve of a holiday | Until 12:00 PM only |
| Shabbat / holiday | None |
| Next regular day | From the normal morning start time |

Implementation:
- [x] **Calendar table:** `03_no_contact_calendar.sql` creates `dbo.omni_no_contact_days` in the **local** database (next to `vw_TestPatients`). There is one row per holiday date: `blocked_from = 12:00` for an eve, `NULL` for a whole-day holiday. **Fridays and Saturdays are built into the logic** and don't need rows. The file also has an insert template and a check query that lists the next 60 days' blocked dates.
- [ ] **Load the holiday dates** from Refuah's closure calendar, once a year, and have Refuah review them.
- [x] **Day-prior query** (`02_day_prior_confirmation_list.sql`): each run covers appointments from tomorrow up to and including the **next run day**, meaning the next day that isn't blocked all day. Fridays and eves are run days, since calls are allowed until 12:00 PM. If today is blocked all day, the query returns no rows.
  - Normal day: Monday's run covers Tuesday.
  - Friday: the run covers Saturday and Sunday. Sunday's run covers Monday.
  - Holiday on Tuesday and Wednesday: Monday's run (the eve) covers Tuesday through Thursday.
- [ ] **Python calling service (next step):** before **every** call, text and retry sent to the PBX, check that the send time is allowed:
  - **Blocked:** from 12:00 PM on Fridays and on dates with `blocked_from = 12:00`, and all day on Saturdays and on dates with `blocked_from IS NULL`.
  - **Allowed again:** at the morning start time of the next regular day.
  - A blocked contact moves to the next allowed time, or is **dropped** if the appointment will already have passed by then.
  - The scheduler that runs the day-prior job must skip whole-day blocked days. The Python check must use the same table and the same Friday/Saturday rule as the SQL, so the two never disagree.

---

## Facilities

Supplied by Refuah (2026-11-08). These are the only sites in scope. The query hard-codes this list in the `sites` CTE in `02_day_prior_confirmation_list.sql`.

| FACILITY_ID | FACILITY_NAME | Address | Routing |
|---|---|---|---|
| 10 | Refuah Health Center (Main) | 728 North Main St., Spring Valley, NY 10977-8916 | by department (x1100 / x1301) |
| 22 | Refuah Health Twin | 5 Twin Ave, Spring Valley, NY 10977-3950 | by department (x1100 / x1301) |
| 41 | Refuah Health Route 59 | 142 Route 59, Monsey, NY 10952-3406 | Hillcrest line x7724 |
| 47 | Wilson | 408 Wilson Ave, New Square, NY 10977-8916 | Wilson line x1160 |

Raw values as supplied (ZIPs were `109778916` and `109773950` without a dash; they're normalized above):

```
10, 'Refuah Health Center'  , '728 North Main St.  Spring Valley  NY  109778916'
41, 'Refuah Health Route 59', '142 Route 59        Monsey         NY  10952-3406'
47, 'Wilson'                , '408 Wilson Ave      New Square     NY  109778916'
22, 'Refuah Health Twin'    , '5 Twin Ave          Spring Valley  NY  109773950'
```

Open points:
- Confirm that **Route 59 (41)** is the site the requirements call "Hillcrest" and that it uses the Hillcrest line x7724.
- **Wilson (47)** has the same ZIP+4 as Main (10977-8916). Confirm it isn't a copy error.

---

## Step-by-step plan

### Step 1: Confirm database access
- The database is **SQL Server**, accessed with SSMS, so direct SQL read access is available. Confirm whether this is the **live eCW database** or a **reporting copy** (replica, Always On readable secondary, or a nightly-restored copy). A nightly copy would be too stale for the "most up-to-date status" re-check.
- Get a **read-only** account (`db_datareader`, or `SELECT` on a dedicated view). Windows/AD login or SQL login, whichever the DBA prefers. Ideally it runs against the reporting copy rather than the live production database.
- Confirm network access from the OmniConnect server to the database, and the HIPAA approval for it.

### Step 2: Discover the schema (`01_schema_discovery.sql`)
- Run the discovery queries (read-only; they return structure and code lists, not PHI).
- Collect: the real column names, appointment status codes, visit type codes, provider specialties and departments, and where alerts, language and guarantor information are stored.

### Step 3: Map every business rule to an eCW field
Fill in this mapping table, one row per rule from the requirements doc:

| Requirement | eCW source | Known? |
|---|---|---|
| Appointment date/time, status | `enc` | Assumed |
| Patient name, DOB, phones | `users` / `patients` | Assumed |
| Provider name | `enc.doctorID` → `users` / `doctors` | Assumed |
| Resource (second appointment under a resource) | `enc.ResourceId` | Assumed |
| Site name + exact address | `enc.facilityId` → supplied site list (see **Facilities**) | **Known** |
| Supported locations (Main, Twin, Route 59/Hillcrest, Wilson) | `enc.facilityId IN (10, 22, 41, 47)` | **Known** |
| Visit type | `enc.VisitType` → `visitcodes` | Assumed |
| Exclude Dental / Optical / Women's Health | `doctors.speciality` list (draft) | **In progress**: confirm basis and list |
| Primary Care (Adult/Family/Peds) vs Specialty, for routing | `doctors.speciality` (placeholder values) | **TBD** |
| New patient flag | `globalalertdetails.AlertId` **95, 117** | **Known** |
| New-patient earlier arrival note | ? | **TBD** |
| Late patient alert | `globalalertdetails.AlertId` **6, 79** | **Known** |
| Late arrival offset (Peds -10 / Adults -15 min) | `arrival_offset_minutes`, from the late alert + `care_group` | **Built**: Peds basis TBD |
| Spanish language alert | alert vs `patients.language`? | **TBD** |
| Family grouping key | `COALESCE(GrId, mobile, home phone)` placeholder | **TBD** |
| Family visit (2+ members, same day) | `family_member_count`, `is_family_visit` | **Built**: depends on the key |
| Test patients | `dbo.vw_TestPatients` (local view) | **Joined, filter missing** |
| High-priority visits (NP, Adult Well, Specialty Consult) | NP = alert 95/117; Well/Consult = visit type placeholders | **Partly known** |
| SMS consent / opt-out | ? | **TBD** |
| All phone numbers on file (multi-contact, Phase 2) | which columns or tables | **TBD** |

### Step 4: Build the base query (day-prior)
- Draft: `02_day_prior_confirmation_list.sql`.
- It returns **one row per appointment**. The application then:
  - groups same-day appointments for one patient (provider + resource) into **one call**
  - groups family members with appointments on the same day into **one call/text** (the query flags these with `is_family_visit`)
  - picks the language, builds the message, and reads out `arrival_time` (the query works out the late-alert offset; the new-patient note is still TBD)

  Grouping in the application keeps the query simple and preserves each appointment ID, which is needed for per-appointment status write-back.

### Step 5: Validate against eCW
- Run the query for 3–5 sample days.
- Compare row counts per facility and per provider with the eCW **Resource Schedule** screen.
- Spot-check about 20 rows for name, phone, address, visit type and flags.
- Confirm that excluded departments and non-PENDING statuses are not in the results.

### Step 6: Refine the derived flags
- Fill in the TBD code lists (visit types, specialties, alerts).
- Re-validate.

### Step 7: Same-day reminder variant
- Same base query, but **all statuses**, and filtered to appointments starting in about 1.5 hours (or pull the whole day once and schedule each reminder).
- Decide quiet hours for early appointments (an 8:00 AM appointment means a 6:30 AM reminder).

### Step 8: Status accuracy check before each call
- The requirement is that calls must use the most up-to-date status when they go out.
- Before every call or text, re-check that single appointment's current status, using a small query by `encounterID` or the API. Skip the contact if the appointment was cancelled or rescheduled in the meantime.

### Step 9: Performance & security
- Confirm that `enc.date` is indexed and measure the query's run time.
- Select only the columns we need (minimum necessary PHI).
- Log every extract in the OmniConnect audit trail.

### Step 10: Sign-off
- You and the client review the query, the validation results, and the answers to the missing info.
- Freeze it as v1.0. Then build the sync service that runs it.

---

## Missing information

### A. Access & environment
1. ~~On-premises or cloud?~~ **Answered:** SQL Server, accessed with SSMS. Still open: is it the live eCW database or a reporting copy, and how current is the copy?
2. ~~Database name and server/instance name.~~ **Answered:** linked server `[ECWNODEAG01].[mobiledoc].[dbo]`, used with four-part names in all queries. Still open: is it a readable secondary or the primary?
3. Can we get a read-only service account, and who approves it?
4. SQL Server version (query 1 in `01_schema_discovery.sql` shows it). The draft uses `CONCAT_WS`, which needs **SQL Server 2017 or later**.
5. **Status write-back:** the query is read-only. How will we write CONFPHONE, CANCSMS, etc. back to eCW: API, HL7 (SIU), or something else? Direct SQL updates to eCW are not recommended.

### B. Schema (most items answered by running `01_schema_discovery.sql`)
6. Actual column names in `enc`, `patients`, `users`, `doctors`, `edi_facilities`, `visitcodes`.
7. Exact eCW code for **PENDING** status (e.g. `PEN`), plus the full list of status codes.
8. Format of `enc.startTime` (TIME, or a text value like `09:30 AM`).
9. How **resources** are stored: as users or doctors, or in a separate table?
10. Where **all phone numbers** are stored (home, mobile, work, additional contacts).

### C. Business rules → eCW codes
11. How to identify **Dental, Optical, Women's Health** so they can be excluded: facility, specialty, department or visit type? List the codes.
12. Is "WH" Women's Health? Please confirm.
13. How to identify **Primary Care (Adults, Family, Pediatrics) vs Specialty**, for routing to x1100 or x1301.
14. Is **Pediatrics vs Adults/Family** (10 vs 15 minutes early) based on department/provider or on patient age?
15. ~~**New patient:** which visit type codes count as "new patient"?~~ **Answered:** a patient alert in `globalalertdetails`, codes 95 and 117. Still open: is the alert removed after the first visit? If it isn't, returning patients would still be flagged as new.
16. **New-patient earlier arrival note:** where is it stored (appointment note, general notes, a custom field), and how is the adjusted time written?
17. ~~**Late patient alert:** where is it stored, and with what exact text or code?~~ **Answered:** `[ECWNODEAG01].[mobiledoc].[dbo].globalalertdetails`, `AlertId` 6 and 79. Still open: whether alerts expire or can be inactivated.
18. **Spanish language alert:** is it a patient alert or the language field? Exact value?
19. **High-priority visits** for the no-show notice and at-risk alerts: which visit type codes are New Patient, Adult Well Visit and Specialty Consult?
20. **Family grouping:** what defines a family? Guarantor, household/account, or a shared phone number? Which phone is used for the combined call? (The query already flags family visits; only the key needs confirming.)
21. ~~Facility IDs and names for **Main, Twin, Hillcrest / Route 59, Wilson**.~~ **Answered:** 10, 22, 41, 47 (see **Facilities**). Still open: is Route 59 (41) the "Hillcrest" site, and is Wilson's ZIP+4 correct?
22. The exact address format to read out (suite, floor?).

### D. Exclusions
23. Should these be excluded: telehealth/virtual visits, deceased patients, inactive patients, patients with no phone? (Test patients: use `dbo.vw_TestPatients`.)
24. **SMS consent / opt-out:** where is it recorded in eCW?
25. Are there visit types or providers to exclude besides Dental, Optical and WH (labs, nurse visits, procedures)?

### E. Timing
26. **Weekends and holidays:** **Partly answered (2026-11-09):** no calls or texts from **12:00 PM on Fridays and the eves of Jewish holidays** until the **morning of the next regular day** (e.g. Friday 12:00 PM → Sunday morning). See **No-contact rule** below. Still open:
    - the holiday list or calendar (can Refuah share theirs?)
    - whether Chol Hamoed and fast days are regular days
    - what time "morning" starts on the next regular day
    - what happens to same-day reminders for appointments on a Friday or eve afternoon
27. **Same-day quiet hours:** what is the earliest allowed reminder time?
28. Exact retry times for "afternoon" and "evening", and the maximum number of attempts.
