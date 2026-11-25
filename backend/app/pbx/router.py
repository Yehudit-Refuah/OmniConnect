import logging

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException

from app.security import require_pbx

from app.conversation import flow

from app.rules.no_contact import can_call_now, current_blocked_days, next_block

from app.rules.eligibility import check_call, current_visits

from app.pbx.models import (Appointment, Call, CallAnswer, CallBatch,
                            CallEvent, ListenSettings, Patient)

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/pbx/v1", dependencies=[Depends(require_pbx)])

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
    """Return the calls the PBX should place now."""
    now = datetime.now().astimezone()
    blocked = current_blocked_days()
    if not can_call_now(now, blocked):
        calls = []  # Shabbat, a holiday, or after 12:00 PM on a Friday or holiday eve
    else:
        # Tell the PBX to stop by the next blocked time, if that comes first.
        stop = next_block(now, blocked)
        calls = [
            c.model_copy(update={"do_not_call_after": min(c.do_not_call_after, stop)})
            for c in FAKE_CALLS[:limit]
        ]
    return CallBatch(batch_id="test-batch", generated_at=now, calls=calls)

# Answers we already gave, so a repeated POST gets the same answer.
# Kept in memory for now; moves to the database in B7.
_answers: dict[tuple[str, int], CallAnswer] = {}


# The call as checked at "dialing": only the visits still due. Moves to the database in B7.
_checked_calls: dict[str, Call] = {}


def find_call(attempt_id: str) -> Call | None:
    if attempt_id in _checked_calls:
        return _checked_calls[attempt_id]
    return next((c for c in FAKE_CALLS if c.attempt_id == attempt_id), None)


@router.post("/calls", response_model=CallAnswer)
def post_call_event(event: CallEvent):
    """The PBX reports what happened; we answer what to say and do next."""
    key = (event.attempt_id, event.sequence)
    if key in _answers:
        return _answers[key]

    call = find_call(event.attempt_id)
    if call is None:
        raise HTTPException(status_code=404, detail="Unknown attempt_id")

    answer = answer_event(event, call)
    _answers[key] = answer
    return answer


def answer_event(event: CallEvent, call: Call) -> CallAnswer:
    """Fixed answers for now. B5 replaces the conversation parts."""
    if event.event == "dialing":
    # Last check right before the phone rings: the time may have passed since GET.
        if not can_call_now(datetime.now().astimezone(), current_blocked_days()):
            return CallAnswer(action="skip", reason="no_contact_day")
        # Is the visit still pending? It may have been cancelled, confirmed or moved since GET.
        try:
            checked = check_call(call, current_visits(call))
        except Exception:
            log.exception("Visit status check failed for %s", call.attempt_id)
            return CallAnswer(action="skip", reason="status_check_failed")  # not sure -> don't call
        if checked is None:
            return CallAnswer(action="skip", reason="visit_not_pending")
        _checked_calls[call.attempt_id] = checked  # the conversation reads only these visits
    return CallAnswer(action="dial")
    if event.event == "answered":
           return flow.start(call)
    if event.event == "voicemail":
        # No names or visit details on voicemail: someone else may hear it.
        return CallAnswer(
            say="Hello, this is Refuah Health calling about an upcoming appointment. "
                "Please call us back. Thank you.",
            language=call.language, action="hangup",
        )
    if event.event == "reply":
           return flow.on_reply(call, event.transcript or "")
    if event.event == "no_input":
           return flow.on_no_input(call)
    return CallAnswer(action="none")  # hangup_by_patient, ended

