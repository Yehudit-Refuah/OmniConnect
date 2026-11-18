# OmniConnect: Project Plan

**Module in scope:** Phase 3, Automated Appointment Confirmations & Reminders
**Owner:** ygarbuz (Refuah Health Center)
**Version:** 1.0 draft, 2026-11-10
**Related:** [eCW query plan](../db/ecw/PLAN.md) · [Getting started guide](GETTING_STARTED.md)

---

## 1. What we are building

A system that calls and texts Refuah patients about their upcoming appointments, understands their answers, and updates eCW. It has a dashboard where managers can see what happened with every appointment.

```
 ┌───────────┐  9:00 AM / 1.5 h before   ┌──────────────────────────────────────────┐
 │    eCW    │ ───── patient list ─────► │            OmniConnect backend           │
 │ (SQL Srv) │                           │              (Python, FastAPI)           │
 │           │ ◄──── status updates ──── │                                          │
 └───────────┘   CONFPHONE, CANCSMS...   │  Scheduler ─► Rules engine ─► Channels   │
                                         │  (jobs)       (grouping,      (voice,     │
                                         │               no-contact,     SMS)        │
                                         │               messages)                   │
                                         │                  │                        │
                                         │                  ▼                        │
                                         │         App database + audit log          │
                                         └──────┬──────────────────────┬────────────┘
                                                │ REST API             │ calls / SMS / transfers
                                                ▼                      ▼
                                   ┌──────────────────────┐   ┌─────────────────────┐
                                   │ Manager dashboard    │   │ Telephony provider  │
                                   │ (React, in browser)  │   │ + Refuah PBX        │
                                   └──────────────────────┘   │ (x1100, x1301,      │
                                                              │  x7724, x1160)      │
                                                              └─────────────────────┘
```

**The main flow, day-prior confirmation:**
1. **9:00 AM:** the scheduler runs the eCW query (`db/ecw/02_day_prior_confirmation_list.sql`) and saves the list.
2. **Rules engine:**
   - groups the patient's own appointments, then family members, into one contact
   - applies the Shabbat/holiday rule
   - chooses the language, works out the arrival time, and adds the no-show notice where it applies
3. **Before each contact:** re-checks the appointment's current status in eCW, then calls or texts.
4. **The patient's answer** (keypad, speech or SMS reply) becomes CONFPHONE, CANCSMS, etc.
5. **Status written back to eCW**, with every step recorded in the audit log.
6. **No answer:** voicemail, then retries in the afternoon and evening.

---

## 2. Technology choices

Your suggestion (GitHub, Python, React) is a good fit. I'd keep it and change a few things from the earlier recommendation to fit Refuah's existing environment:

| Layer | Choice | Why |
|---|---|---|
| **Code hosting** | **GitHub**, private repository in a Refuah organization | Version history, code review and automated checks (GitHub Actions). |
| **Backend** | **Python 3.13 + FastAPI** | You already run Python at Refuah (e.g. the treatment-plan PDF job). FastAPI is simple and fast, and generates its own API documentation page. |
| **Database access** | **SQLAlchemy + pyodbc**, with **Alembic** for schema changes | The same `pyodbc` driver you already use, plus a standard way to version database changes. |
| **App database** | **SQL Server** (changed from PostgreSQL) | You already have it, know SSMS, and back it up. The eCW data arrives through the same linked server. PostgreSQL only matters for the AI phases later. |
| **Scheduler** | **APScheduler**, inside a separate "worker" process | Runs the 9:00 AM job, same-day reminders and retries in Python, next to the rules. Simpler than splitting the logic across SQL Agent jobs. |
| **Frontend** | **React + TypeScript**, built with **Vite** | The standard choice for dashboards. TypeScript catches mistakes before you run the code. |
| **UI components** | **Mantine** | Ready-made tables, forms, date pickers and charts, so you write very little CSS. Easier to learn than most alternatives. |
| **Data fetching (UI)** | **TanStack Query** | Handles loading and auto-refresh for the live counts with very little code. |
| **Staff login** | **Microsoft Entra ID** (MSAL) | Staff use their Refuah Microsoft account. Roles (manager, supervisor, viewer) come from AD groups. |
| **Telephony / SMS** | **To decide** once the PBX is known (see §6) | Transfers to x1100/x1301/x7724/x1160 have to go through the PBX, so the PBX decides the design. Candidates: Azure Communication Services or Twilio (with a BAA), connected to the PBX by SIP; or the PBX's own API. |
| **Hosting** | **On-prem Windows server** to start (changed from Azure) | eCW and SQL Server are on the internal network, and the dashboard users are on-site. This avoids building a cloud-to-on-prem connection for Phase 3. Azure stays an option later. |
| **Automated checks** | **GitHub Actions**: Ruff (Python lint), pytest, ESLint, TypeScript build | Every change is checked automatically before it's merged. |

**Alternatives I considered and don't recommend here:**
- **Streamlit or Power BI for the dashboard:** quick to start, but weak on per-user roles, audit and two-way actions. Fine for one-off reports, not for this.
- **C# / .NET:** also a good fit for a Microsoft shop, but you already know Python.
- **Next.js instead of plain React:** it adds server-rendering concepts you don't need for an internal dashboard.

> **HIPAA:** GitHub is not where PHI goes. Code, SQL and docs only: no patient data in the repo, in issues, in screenshots or in test files. Test data must be fake. Check with Refuah compliance whether a GitHub BAA is needed at all; if nothing in GitHub contains PHI, it usually isn't.

---

## 3. Repository layout

One repository, `omniconnect`, holds everything:

```
omniconnect/
├── README.md                  ← what the project is, how to run it
├── .gitignore                 ← files Git must never save (.env, venv, node_modules)
├── .env.example               ← list of settings, no real values
├── docs/
│   ├── PROJECT_PLAN.md        ← this file
│   ├── GETTING_STARTED.md     ← beginner setup & daily workflow
│   └── decisions/             ← one short note per big decision (e.g. "001-telephony.md")
├── db/
│   ├── ecw/                   ← eCW queries (01, 02, 03) + PLAN.md  (exists today)
│   └── migrations/            ← Alembic: OmniConnect's own tables
├── backend/
│   ├── requirements.txt
│   ├── app/
│   │   ├── main.py            ← FastAPI app (dashboard API)
│   │   ├── worker.py          ← scheduler process (jobs, calls, retries)
│   │   ├── config.py          ← reads settings from .env
│   │   ├── db.py              ← database connections (app DB + eCW)
│   │   ├── models/            ← tables as Python classes
│   │   ├── ecw/               ← read patient list, re-check status, write status back
│   │   ├── rules/             ← grouping, no-contact calendar, arrival time, messages
│   │   ├── channels/          ← voice, SMS, PBX transfer (one adapter per provider)
│   │   ├── api/               ← endpoints the dashboard calls
│   │   └── audit/             ← append-only event log
│   └── tests/                 ← pytest tests, fake data only
├── frontend/
│   ├── package.json
│   └── src/
│       ├── pages/             ← Dashboard, Appointment timeline, Search, Settings
│       ├── components/        ← reusable pieces (status badge, timeline item...)
│       └── api/               ← functions that call the backend
└── .github/
    └── workflows/ci.yml       ← automated checks on every pull request
```

---

## 4. App database (main tables)

These are OmniConnect's own tables, separate from eCW:

| Table | Holds |
|---|---|
| `appointment_snapshot` | The eCW query result for each run: one row per appointment, as it was when pulled |
| `contact` | One planned outreach (a call or SMS) that may cover several appointments (same patient, or a family) |
| `contact_appointment` | Links a contact to its appointments, so each appointment gets its own status |
| `contact_attempt` | Each try: time, channel, phone number, result (answered, voicemail, busy, failed) |
| `audit_event` | **Append-only** timeline: every action, response, transfer and status change, with a timestamp. Never updated or deleted. |
| `ecw_status_update` | Write-back queue: appointment, new code, state (queued, sent, confirmed, failed), retries |
| `omni_no_contact_days` | Shabbat/holiday calendar (exists: `db/ecw/03_no_contact_calendar.sql`) |
| `job_run` | Each scheduler run: start, end, row counts, errors |
| `message_template` | English and Spanish message texts, editable without changing code |

---

## 5. Milestones

Each milestone ends with something that works and can be shown. **Nothing calls a real patient until milestone 9.** Before that, everything runs in **dry-run mode**: the system decides what it would do and shows it on the dashboard, but doesn't send it.

### M0: Foundations
- Install the tools (see `GETTING_STARTED.md`). Create the GitHub organization and the private repo, with branch protection on `main`.
- Move the existing `db/ecw` files into the repo as the first commit.
- Skeleton: a FastAPI app with a `/health` endpoint, and a React page that shows "backend is up".
- CI workflow runs the lint and tests on every pull request.
- **Start the long-lead items now** (§6): eCW write-back method, PBX identification, telephony vendor and BAA.
- ✅ **Done when:** a pull request shows green checks, and both apps run on your PC.

### M1: Patient list sync
- Finish the eCW query (`db/ecw/PLAN.md` Query TODO) and make it a stored procedure.
- A worker job runs it at 9:00 AM, saves the rows to `appointment_snapshot`, and records a `job_run` row.
- ✅ **Done when:** 5 sample days match eCW's Resource Schedule screen.

### M2: Rules engine and dry run
- Group a patient's same-day appointments into one contact, then family members.
- Apply the no-contact rule (Friday/eve 12:00 PM → next regular day); the same rule must be used before every send.
- Build the message: name, provider, time, site and address, visit type (left out for new patients), arrival time, no-show notice. English and Spanish templates.
- **Unit tests** for every rule, using fake patients.
- ✅ **Done when:** the dry run produces the list of planned contacts, with full messages, for a real day, and a manager agrees it's right.

### M3: Manager dashboard v1 (read-only)
- Entra ID login and roles.
- Pages:
  - **Today/Tomorrow:** counts by status, site and provider
  - **Search:** by name, MRN, phone, provider, site or date
  - **Appointment timeline:** the audit events for one appointment
- ✅ **Done when:** managers can log in and review the dry-run results.

### M4: SMS channel (test phones only)
- Telephony vendor connected under a BAA. Send texts and receive replies.
- Reply parsing: the keyword lists from the requirements (Yes/OK/Confirmed…, No/Cancel…), and a "reschedule" path.
- An allow-list of **staff test phone numbers**: messages to any other number are blocked in code.
- ✅ **Done when:** staff test phones receive texts and their replies show up correctly in the timeline.

### M5: Voice channel and transfers (test phones only)
- Outbound call with text-to-speech, keypad (and optionally speech) answers, voicemail detection with the voicemail message.
- Transfers to x1100 / x1301 / x7724 / x1160 through the PBX, with wait-time estimates.
- ✅ **Done when:** test calls cover every path: confirm, cancel, reschedule-transfer, voicemail and no answer.

### M6: eCW status write-back
- Write-back through the method Refuah approves (API, HL7, or an existing integration such as the one behind `sp_queueECWDocumentUpload`).
- Queue with retries, plus a daily reconciliation report of what was sent versus what eCW shows.
- ✅ **Done when:** test appointments in eCW show CONFPHONE, CANCSMS, MSNGRVCMSG, etc. correctly.

### M7: Same-day reminders, retries and pre-send check
- Same-day reminders 1.5 hours before (all statuses; status changes only on an explicit confirm or cancel).
- Afternoon and evening retries; the eCW status re-check right before every contact; quiet hours.
- ✅ **Done when:** a full simulated day runs correctly in dry run.

### M8: Callback line (inbound)
- A patient calls back, the system verifies their identity, then confirms or cancels (CONFPHONE / CANCPHONE).
- ✅ **Done when:** test callbacks work end to end.

### M9: Pilot and go-live
- **Pilot:** one site, a few providers, real patients, staff watching the dashboard daily.
- Then all 4 sites. At-risk alerts (9:00 PM cutoff), metrics, CSV/Excel audit export.
- ✅ **Done when:** 2 clean weeks at all sites, with sign-off from Refuah.

---

## 6. Long-lead items: start in M0

These depend on other people and can block the build for weeks:

| Item | Why it matters | Who |
|---|---|---|
| **eCW status write-back method** (API / HL7 / existing integration) | Without it, nothing updates eCW (M6). eCW API write access often needs partner approval. | Refuah IT + eCW |
| **Which PBX** handles the extensions, and does it have an API or SIP? | Decides the telephony design (M4–M5). | Refuah IT / telecom |
| **Telephony/SMS vendor + BAA** | Required before any patient data reaches the vendor. | Compliance + vendor |
| **TCPA / SMS consent rules** | Legal basis for automated calls and texts. | Compliance |
| **Server, service accounts, read-only eCW access** | Needed to run anything outside your PC. | Refuah IT / DBA |
| **Open business questions** | The client email (Sunday rule, labs and vaccines, quiet hours, ...). | Client |

---

## 7. How we work

- **Branches:** `main` is always working. Each task gets its own branch (`feature/sms-replies`), merged with a pull request after the checks pass.
- **Small steps:** one milestone item per branch, committed often, with clear messages ("Add family grouping rule").
- **Settings and secrets** go in `.env` files on each machine, never in Git. `.env.example` lists the setting names.
- **Environments:**
  - **Dev:** your PC, fake data plus read-only eCW
  - **Test:** a server, test phones only
  - **Prod:** live
  The same code runs in all three; only the settings change.
- **Decisions** are written down in `docs/decisions/` (what was decided, why, and when).
- **Working with Claude Code:** ask for one milestone item at a time, review every change before committing, and ask "explain this" whenever something isn't clear.
