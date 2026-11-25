from datetime import timedelta

import pytest

from app.pbx.router import FAKE_CALLS
from app.rules.eligibility import PENDING, VisitNow, check_call

CALL = FAKE_CALLS[0]
APPT = CALL.patients[0].appointments[0]


def visits(status=PENDING, moved=timedelta(0), deleted=False):
    return {APPT.appointment_id: VisitNow(status, APPT.visit_datetime + moved, deleted)}


def test_still_pending_is_called():
    assert check_call(CALL, visits()) == CALL


@pytest.mark.parametrize("change", [
    {"status": "CANC"},              # cancelled by an operator
    {"status": "CONFSMS"},           # confirmed some other way
    {"deleted": True},               # deleted from the schedule
    {"moved": timedelta(hours=2)},   # moved to another time
])
def test_changed_visit_is_skipped(change):
    assert check_call(CALL, visits(**change)) is None


def test_visit_not_found_is_skipped():
    assert check_call(CALL, {}) is None


def test_only_the_visits_still_due_are_kept():
    second = APPT.model_copy(update={"appointment_id": 1002})
    patient = CALL.patients[0].model_copy(update={"appointments": [APPT, second]})
    two_visits = CALL.model_copy(update={"patients": [patient]})
    checked = check_call(two_visits, {1002: VisitNow(PENDING, APPT.visit_datetime)})
    assert [a.appointment_id for p in checked.patients for a in p.appointments] == [1002]
