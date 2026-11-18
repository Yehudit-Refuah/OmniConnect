# OmniConnect: Summary and step-by-step to-do list

*Last updated: 2026-11-18*

Tick a box (`[ ]` becomes `[x]`) when a step is done. Run all commands in the VS Code terminal (**Terminal → New Terminal**), with the `OmniConnect` folder open (**File → Open Folder**).

> ### 📍 You are here: **B1, step 2**
> Git setup is finished and the project is on GitHub. The backend packages are installed. Next: remove the unused `src` folder, then create `backend/app/main.py`.

---

## Summary

**OmniConnect** places automatic appointment confirmation calls for Refuah Health. The PBX (built by another team) runs the schedule. It fetches the call list from our API (`GET /api/pbx/v1/calls`), calls the patients, and sends back what happened (`POST /api/pbx/v1/calls`). For every POST, our API answers with what to say next and what to do.

**Decisions so far:**
- Patients answer in their own words. We work out what they meant: simple word matching first, then Claude for unclear replies.
- Unclear answers go to an operator.
- Cancel requests: read back "You'd like to cancel your appointment on Monday at 9:30, is that right?", then transfer to an operator. **The visit is not changed.**
- Only **CONFPHONE** (confirmed) is written back to eCW for now, and only if the visit is still pending.
- No calls from 12:00 PM on Fridays and holiday eves until the next regular day (table `omni_no_contact_days`).
- Stack: Python 3.13 + FastAPI (using uv), SQL Server, React later for the screens, GitHub (private repo `Yehudit-Refuah/OmniConnect`).

**Safety rules, always:**
- No patient data in Git, ever: no real names, phones, MRNs, query results, screenshots or exports, not even inside comments.
- Passwords and keys only in `.env`, which is never committed.
- Tests use fake data only (`Test Patient`, `TEST000001`, `+18455550100`).

**Already done:**
- The three eCW queries in `db/ecw/`.
- The docs: `DEVELOPMENT_PLAN.md`, `PBX_INTEGRATION_API.md` (for the PBX team), `call_flow_diagram.html`, `GETTING_STARTED.md`.
- Git, uv and Python are installed.
- Git setup is finished: the private repo `Yehudit-Refuah/OmniConnect` holds the first commit.
- The backend project is created and its packages are installed (B1 step 1).

---

## A. Git setup ✅ (finished)

All of A is done. It's kept here for reference.

### A1. `git init`
- [x] Done

### A2. Create `.gitignore`
- [x] Done

This file tells Git which files must never be uploaded.

1. In VS Code's file list (left side), right-click on empty space under the files, or on the **OMNICONNECT** title, and choose **New File**.
2. Name it exactly `.gitignore`: with the dot at the start and no `.txt` at the end.
3. Paste this in and save (**Ctrl+S**):
   ```
   # Secrets and settings
   .env
   *.env
   !.env.example

   # Python
   .venv/
   __pycache__/
   *.pyc
   .pytest_cache/
   .ruff_cache/

   # React / Node
   node_modules/
   frontend/dist/

   # Never commit patient data or query exports
   *.csv
   *.xlsx
   exports/
   ```

**Check it worked:** the file is at the top level, next to `CHAT_LOG_...md`, not inside `db` or `docs`.

### A3. Remove the real ID from the query ⚠️
- [x] Done

1. Open `db/ecw/02_day_prior_confirmation_list.sql`.
2. Press **Ctrl+G**, type `268`, press **Enter**.
3. That line is a commented-out debug filter, `--where s1.family_group_key = '...'`, with a real family key in it. Click on the line and press **Ctrl+Shift+K** to delete it, or replace the key with `TEST000001`.
4. Save (**Ctrl+S**).

**Check it worked:** press **Ctrl+Shift+F**, search for the real key, and you should get no results.

**Debugging a real family later:** paste the real key in temporarily, then change it back to `TEST000001` before you commit.

**Why:** it's a real patient identifier. Once something is committed, it stays in Git history even if you delete it later.

### A4. Choose what to save (stage)
- [x] Done

```powershell
git add .
git status
```

**Check it worked:** the green list under "Changes to be committed" should contain only:
- `.gitignore`
- `CHAT_LOG_2026-11-08.md`
- files in `db/ecw/`
- files in `docs/`

If you see anything ending in `.csv`, `.xlsx`, `.env`, `.png` or `.jpg`, **stop**. Run `git reset` to unstage everything, then ask Claude.

### A5. Save a snapshot (commit)
- [x] Done

```powershell
git commit -m "Initial commit: eCW queries and project docs"
```

**Check it worked:** `git log --oneline` shows one line with your message.

### A6. Connect to GitHub and upload (push)
- [x] Done

```powershell
git remote add origin https://github.com/Yehudit-Refuah/OmniConnect.git
git push -u origin main
```

- A sign-in window opens the first time. Choose **Sign in with your browser** and log in as **Yehudit-Refuah**.
- `-u` remembers the connection, so from now on a plain `git push` is enough.

**Check it worked:** refresh the repo page on GitHub. The `db` and `docs` folders should be there, and the label should still say **Private**.

**Common errors:**
| Message | Fix |
|---|---|
| `remote origin already exists` | Run `git remote set-url origin https://github.com/Yehudit-Refuah/OmniConnect.git`, then push again. |
| `src refspec main does not match any` | The commit (A5) didn't happen. Do A5 first. |
| `Repository not found` / `403` | You're signed in with a different GitHub account. Ask Claude how to switch accounts. |

### Lesson learned: fixing something committed by mistake
If something that shouldn't be there gets into your **last** commit, remove it from the file, then:
```powershell
git add .
git commit --amend --no-edit
```
- **Not pushed yet:** that's all you need.
- **Already pushed, and you're the only one using the repo:** also run `git push --force`. Avoid `--force` once teammates share the repo; ask first.

Before every commit, check the staged files for any ID you pasted in while debugging: `git grep --cached <the-id>` should print nothing.

---

## B. Build the API

From here on, each step is: **build it, run it, test it, commit it.** Use the commit routine at the end of every step:

```powershell
git add .
git status          # check: no .env, no real data
git commit -m "Short description of what you did"
git push
```

### B1. Backend skeleton + health endpoint ← 📍 you are here

**What you get:** a running API with one address, `/api/health`, that answers `{"status": "ok"}`.

#### B1.1 Create the backend project and install the packages
- [x] Done

```powershell
cd C:\Users\ygarbuz\Projects\OmniConnect
uv init backend --app --python 3.13
cd backend
uv add "fastapi[standard]" sqlalchemy pyodbc apscheduler python-dotenv
uv add --dev pytest ruff
```

#### B1.2 Remove the parts `uv init` added that we don't use
- [ ] Done

Your uv version created a `src/` folder. We keep our code in an `app` folder instead.

1. In VS Code's file list, right-click `backend/src` → **Delete**.
2. Open `backend/pyproject.toml` and delete these lines, then save (**Ctrl+S**):
   ```toml
   [project.scripts]
   backend = "backend:main"

   [build-system]
   requires = ["uv_build>=0.13.8,<0.14.0"]
   build-backend = "uv_build"
   ```
3. In the terminal:
   ```powershell
   cd C:\Users\ygarbuz\Projects\OmniConnect\backend
   uv sync
   ```

**Check it worked:** `uv sync` finishes without errors, and `pyproject.toml` has only the `[project]` and `[dependency-groups]` sections left.

#### B1.3 Create the `app` folder and its two files
- [ ] Done

1. Right-click the `backend` folder → **New Folder** → name it `app`.
2. Right-click `app` → **New File** → `__init__.py`. Leave it empty and save. It tells Python that `app` is a package.
3. Right-click `app` → **New File** → `main.py`. Paste this and save:
   ```python
   from fastapi import FastAPI

   app = FastAPI(title="OmniConnect API")


   @app.get("/api/health")
   def health():
       """Simple check that the API is running."""
       return {"status": "ok"}
   ```

**Check it worked:** the file list shows `backend/app/__init__.py` and `backend/app/main.py`.

#### B1.4 Run it
- [ ] Done

Run this from inside the `backend` folder:
```powershell
uv run fastapi dev app/main.py
```
Wait until you see `Uvicorn running on http://127.0.0.1:8000`.

**Check it worked:**
- Open http://localhost:8000/api/health in your browser. You should see `{"status":"ok"}`.
- Open http://localhost:8000/docs to see automatic, clickable API docs.
- Stop the server with **Ctrl+C** in the terminal.

**If you get an error:** copy the terminal text and paste it to Claude.

#### B1.5 Save and upload
- [ ] Done

From the project folder:
```powershell
cd C:\Users\ygarbuz\Projects\OmniConnect
git add .
git status
```
**Check:** the new files should all be in `backend/` (`app/`, `pyproject.toml`, `uv.lock`, `README.md`, `.python-version`) plus `docs/TODO.md`. There should be **no `.venv`** in the list, because `.gitignore` hides it.

Then:
```powershell
git commit -m "Add backend skeleton with health endpoint"
git push
```

**Check it worked:** on GitHub, the `backend` folder appears.

### B2. GET /calls with fake data
- [ ] Done

**What you get:** the PBX address returns a call list in exactly the format promised in `PBX_INTEGRATION_API.md` §4.1, using fake calls for now.

1. Create `backend/app/pbx/__init__.py` (empty).
2. Create `backend/app/pbx/models.py`. This describes the JSON shapes in Python, using Pydantic (it comes with FastAPI):
   ```python
   from datetime import datetime

   from pydantic import BaseModel


   class Appointment(BaseModel):
       appointment_id: int
       visit_datetime: datetime
       arrival_datetime: datetime
       facility: str
       facility_address: str
       provider: str


   class Patient(BaseModel):
       patient_name: str
       mrn: str
       appointments: list[Appointment]


   class Call(BaseModel):
       attempt_id: str
       call_id: int
       attempt_number: int
       call_type: str
       phone: str
       language: str
       operator_extension: str
       do_not_call_after: datetime
       patients: list[Patient]


   class CallBatch(BaseModel):
       batch_id: str
       generated_at: datetime
       calls: list[Call]
   ```
3. Create `backend/app/pbx/router.py`, with the endpoint and **fake** data only:
   ```python
   from datetime import datetime

   from fastapi import APIRouter

   from app.pbx.models import Appointment, Call, CallBatch, Patient

   router = APIRouter(prefix="/api/pbx/v1")

   FAKE_CALLS = [
       Call(
           attempt_id="a-test-0001",
           call_id=5001,
           attempt_number=1,
           call_type="day_prior_confirmation",
           phone="+18455550100",
           language="en-US",
           operator_extension="1100",
           do_not_call_after=datetime.fromisoformat("2026-11-17T20:00:00-05:00"),
           patients=[
               Patient(
                   patient_name="Test Patient",
                   mrn="TEST000001",
                   appointments=[
                       Appointment(
                           appointment_id=1001,
                           visit_datetime=datetime.fromisoformat("2026-11-18T09:30:00-05:00"),
                           arrival_datetime=datetime.fromisoformat("2026-11-18T09:15:00-05:00"),
                           facility="Test Facility",
                           facility_address="1 Test St, Spring Valley, NY 10977",
                           provider="Dr. Example",
                       )
                   ],
               )
           ],
       )
   ]


   @router.get("/calls", response_model=CallBatch)
   def get_calls(limit: int = 50):
       """Return the calls the PBX should place now (fake data for now)."""
       return CallBatch(
           batch_id="test-batch",
           generated_at=datetime.now().astimezone(),
           calls=FAKE_CALLS[:limit],
       )
   ```
4. Connect the router in `backend/app/main.py` by adding these lines:
   ```python
   from app.pbx.router import router as pbx_router

   app.include_router(pbx_router)
   ```

**Check it worked:** run the server, open http://localhost:8000/docs, click **GET /api/pbx/v1/calls → Try it out → Execute**. The answer should look like the example in `PBX_INTEGRATION_API.md` §4.1.

**Commit:** `git commit -m "Add GET /calls with fake data"`

### B3. POST /calls (receive what happened)
- [ ] Done

**What you get:** the PBX can report events (`dialing`, `answered`, `reply`, `ended`…) and always gets back the `say` + `action` answer described in §4.2.

**How:**
1. In `models.py`, add a `CallEvent` model for the request (attempt_id, sequence, event, occurred_at, plus optional transcript and `ended` fields) and a `CallAnswer` model for the response (say, language, action, listen, transfer_to, transfer_note, reason).
2. In `router.py`, add `@router.post("/calls", response_model=CallAnswer)`.
3. Start with simple fixed answers per event: `dialing` → `dial`, `answered` → opening text + `listen`, `voicemail` → voicemail text + `hangup`, `ended` → `none`.
4. Duplicates: keep the answers in a dictionary keyed by `(attempt_id, sequence)`. If the same pair comes again, return the saved answer. This moves into the database in B7.

**Check it worked:** in `/docs`, POST a `dialing` event and then an `answered` event, and look at the answers. Send the same one twice and you should get the identical answer.

**Commit:** `git commit -m "Add POST /calls with basic event answers"`

### B4. Security: API key + IP allowlist
- [ ] Done

**What you get:** only the PBX can use the API.

**How:**
1. Create `backend/.env`. It's already covered by `.gitignore`, so it will never be committed:
   ```ini
   PBX_API_KEY=make-up-a-long-random-test-key
   PBX_ALLOWED_IPS=127.0.0.1
   ```
2. Create `backend/.env.example` with the same names and fake values. This one **is** committed, so others know which settings exist.
3. Add a FastAPI dependency that checks the `X-API-Key` header and the caller's IP address, and returns `401` / `403` if they don't match. Attach it to the PBX router.

**Check it worked:** in `/docs`, a call without the key gets `401`; click **Authorize**, enter the key, and it works.

**Commit:** `git commit -m "Protect PBX endpoints with API key and IP allowlist"` (check that `.env` is **not** in `git status`).

### B5. Conversation logic
- [ ] Done

**What you get:** the real conversation from `call_flow_diagram.html`.

**How:**
1. Create `backend/app/conversation/` with:
   - `intent.py`: turns the patient's words into one of `confirm`, `cancel`, `reschedule` or `unclear`. First try word lists ("yes", "I'll be there", "cancel"…); if nothing matches, ask Claude, which answers with one of the four labels only.
   - `flow.py`: decides the next answer:
     - confirm → thank you + `hangup`, and mark CONFPHONE
     - cancel → read the appointment back ("is that right?"); yes → `transfer`, and **don't change the visit**
     - reschedule or unclear → `transfer` with a short `transfer_note`
     - silence twice → `transfer`
2. Call `flow.py` from POST `/calls` for `reply` and `no_input` events.
3. The Claude API key goes in `.env` only. **Before sending real patient replies to Claude, the BAA (patient-data agreement) must be confirmed by IT/compliance.** Until then, test with fake sentences only.

**Check it worked:** write tests (B8) with sentences like "yeah we'll be there", "I need to cancel", "what?", and check each answer.

**Commit:** `git commit -m "Add reply understanding and conversation flow"`

### B6. No-contact day check in Python
- [ ] Done

**What you get:** no calls are handed out from 12:00 PM on Fridays and holiday eves, or on Saturdays and holidays.

**How:**
1. Create `backend/app/rules/no_contact.py` with a function `can_call_now(now, blocked_days) -> bool`. It uses the same rules as `03_no_contact_calendar.sql`: Saturdays, whole-day rows, and `blocked_from` times.
2. In GET `/calls`, return an empty list when `can_call_now` is false. Set each call's `do_not_call_after` to the next blocked time.
3. In POST `dialing`, answer `skip` with `reason: "no_contact_day"` if the time has passed.

**Check it worked:** tests for a Friday at 11:59 AM (allowed), a Friday at 12:00 PM (blocked), a Saturday (blocked), and a Sunday morning (allowed).

**Commit:** `git commit -m "Add no-contact day rule"`

### B7. Connect to SQL Server
- [ ] Done

**What you get:** real calls from the day-prior query instead of fake ones, and every event saved.

**How:**
1. Add the connection string to `.env` (`OMNI_DB_URL=...`; see `GETTING_STARTED.md` §4, "Settings and secrets").
2. Create the OmniConnect tables in the local database (`omni` schema): calls, attempts, events, results.
3. A daily job (APScheduler) runs the day-prior query and fills the calls table.
4. GET `/calls` reads from the table and reserves the calls; POST saves every event. The duplicate check moves from the dictionary to the database.
5. Start in **allowlist mode** (`ALLOWLIST_MODE=true`), so that only test patients are ever handed to the PBX.

**Check it worked:** with allowlist mode on, GET `/calls` returns only test patients.

**Commit:** `git commit -m "Load calls from SQL Server and save events"`

### B8. Tests + fake PBX
- [ ] Done (and keep adding as you go)

**How:**
1. Put tests in `backend/tests/`, one file per area (`test_intent.py`, `test_no_contact.py`, `test_pbx_api.py`). FastAPI's `TestClient` lets you call the endpoints without starting the server.
2. Run them with `uv run pytest`. All must pass before every commit.
3. `backend/scripts/fake_pbx.py`: a small script that acts like the PBX (GET the calls, then POST `dialing`, `answered`, a typed-in reply, and `ended`), so you can test a whole call from your PC.
4. Check code style: `uv run ruff format` then `uv run ruff check`.

### B9. Write CONFPHONE back to eCW
- [ ] Done

**How:**
- When a call ends with a confirmation, update the visit status to **CONFPHONE**, but only if it's still **PENDING**.
- Controlled by the setting `ecw_writeback_codes=CONFPHONE`. Other codes are saved only in OmniConnect for now.
- Test on the test patients first, and get approval before turning it on for everyone.

---

## C. Open items

| | Task | How |
|---|---|---|
| [ ] | Filter out test patients in the day-prior query | In `02_day_prior_confirmation_list.sql`, the `vw_TestPatients` join needs `AND tp.patientId IS NULL` in the WHERE clause (or the reverse, for allowlist testing). Ask Claude to walk through it. |
| [ ] | Send the PBX document and diagram to the PBX team | Attach `docs/PBX_INTEGRATION_API.md` and `docs/call_flow_diagram.html` (or a screenshot of it) and ask for answers to §10, "Questions for the PBX team". |
| [ ] | Ask IT for a test server | It needs to run Python and reach SQL Server, and it needs a fixed address the PBX can reach over HTTPS. |
| [ ] | Ask IT/compliance about the Claude BAA | It must be confirmed before real patient replies are sent to Claude (B5). |
| [ ] | Manager's answer on the team's GitHub setup | If there's a company organization, move the repo there: repo **Settings → Transfer ownership**. History is kept. |
| [ ] | Clean up the docs | Regenerate `DEVELOPMENT_PLAN.html` from the `.md`, and delete the outdated `PROJECT_PLAN.md` (`git rm docs/PROJECT_PLAN.md`, then commit). |

---

## Daily routine (once the first push is done)

```powershell
git pull                          # 1. get the latest version
# 2. work, save files, run: uv run pytest
git add .
git status                        # 3. check: no .env, no real data
git commit -m "What you did"      # 4. save a snapshot
git push                          # 5. upload
```

See `GETTING_STARTED.md` §7 for working with branches, and §8 for "Help, I broke something".
