"""Right before dialing: is each visit still waiting for a confirmation?
A patient or an operator may have cancelled, confirmed or moved it since the morning list."""
from datetime import datetime
from typing import NamedTuple

from app.pbx.models import Call

PENDING = "PEN"  # TBD: the exact eCW code, same as @status_pending in 02_day_prior_confirmation_list.sql


class VisitNow(NamedTuple):
    """How the visit looks in eCW right now."""
    status: str
    visit_datetime: datetime
    deleted: bool = False


def still_due(visit_datetime: datetime, now: VisitNow | None) -> bool:
    """Still pending, not deleted, and still at the time we would read out."""
    return (now is not None
            and not now.deleted
            and now.status == PENDING
            and now.visit_datetime == visit_datetime)


def check_call(call: Call, visits: dict[int, VisitNow]) -> Call | None:
    """The call with only the visits that are still due, or None if none are left."""
    patients = []
    for patient in call.patients:
        appts = [a for a in patient.appointments
                 if still_due(a.visit_datetime, visits.get(a.appointment_id))]
        if appts:
            patients.append(patient.model_copy(update={"appointments": appts}))
    if not patients:
        return None
    return call.model_copy(update={"patients": patients})


# ---------- Where the current status comes from ----------
# Until B7: fake statuses. From B7 on: one quick query to eCW for these appointment IDs
# (db/ecw/04_visit_status_now.sql).

FAKE_VISITS = {
    1001: VisitNow(PENDING, datetime.fromisoformat("2026-11-18T09:30:00-05:00")),
}


def current_visits(call: Call) -> dict[int, VisitNow]:
    ids = [a.appointment_id for p in call.patients for a in p.appointments]
    return {i: FAKE_VISITS[i] for i in ids if i in FAKE_VISITS}
