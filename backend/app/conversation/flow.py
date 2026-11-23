"""Decide what to say and do next in the conversation."""

from dataclasses import dataclass
from datetime import datetime

from app.conversation.intent import understand_reply, yes_or_no
from app.pbx.models import Call, CallAnswer, ListenSettings

QUESTION = "Can you make it? Please say confirm, cancel, or reschedule."
MAIN_HINTS = ["confirm", "cancel", "reschedule", "yes", "no"]
YES_NO_HINTS = ["yes", "no"]


@dataclass
class Conversation:
    """Where one call is in the conversation."""
    stage: str = "question"  # "question" or "cancel_check"
    silences: int = 0
    result: str | None = None  # "CONFPHONE" when confirmed


# One Conversation per attempt_id. In memory for now; moves to the database in B7.
_conversations: dict[str, Conversation] = {}


def get_conversation(attempt_id: str) -> Conversation:
    return _conversations.setdefault(attempt_id, Conversation())


# ---------- Building sentences ----------

def spoken_time(dt: datetime) -> str:
    """2026-11-18 09:30 -> 'Wednesday, November 18 at 9:30 AM'."""
    am_pm = "AM" if dt.hour < 12 else "PM"
    return f"{dt:%A}, {dt:%B} {dt.day} at {dt.hour % 12 or 12}:{dt:%M} {am_pm}"


def appointment_details(call: Call) -> str:
    sentences = []
    for patient in call.patients:
        first_name = patient.patient_name.split()[0]
        for appt in patient.appointments:
            s = (f"{first_name} has an appointment with {appt.provider} at "
                 f"{appt.facility} on {spoken_time(appt.visit_datetime)}.")
            if appt.arrival_datetime < appt.visit_datetime:
                s += f" Please arrive by {appt.arrival_datetime.hour % 12 or 12}:{appt.arrival_datetime:%M}."
            sentences.append(s)
    return " ".join(sentences)


def cancel_check_question(call: Call) -> str:
    appts = [a for p in call.patients for a in p.appointments]
    if len(appts) == 1:
        which = f"your appointment on {spoken_time(appts[0].visit_datetime)}"
    else:
        which = "these appointments"
    return f"You'd like to cancel {which}, is that right?"


def operator_note(reason: str, call: Call) -> str:
    """Short note for the operator, e.g. 'Wants to cancel: Test Patient, Wed 11/18 9:30 AM, Dr. Example'."""
    patient = call.patients[0]
    appt = patient.appointments[0]
    when = f"{appt.visit_datetime:%a %m/%d} {appt.visit_datetime.hour % 12 or 12}:{appt.visit_datetime:%M} {'AM' if appt.visit_datetime.hour < 12 else 'PM'}"
    return f"{reason}: {patient.patient_name}, {when}, {appt.provider}"


# ---------- Building answers ----------

def listen(call: Call, say: str, hints: list[str] = MAIN_HINTS) -> CallAnswer:
    return CallAnswer(say=say, language=call.language, action="listen",
                      listen=ListenSettings(hints=hints))


def transfer(call: Call, reason: str) -> CallAnswer:
    return CallAnswer(
        say="Please hold while I transfer you to a staff member.",
        language=call.language, action="transfer",
        transfer_to=call.operator_extension,
        transfer_note=operator_note(reason, call),
    )


# ---------- The conversation ----------

def start(call: Call) -> CallAnswer:
    """A person answered: greet, read the appointment, ask the question."""
    get_conversation(call.attempt_id).stage = "question"
    say = (f"Hello, this is Refuah Health calling to confirm an appointment. "
           f"{appointment_details(call)} {QUESTION}")
    return listen(call, say)


def on_reply(call: Call, transcript: str) -> CallAnswer:
    if not transcript.strip():
        return on_no_input(call)
    conv = get_conversation(call.attempt_id)
    conv.silences = 0

    # Step 2: we asked "You'd like to cancel..., is that right?"
    if conv.stage == "cancel_check":
        if yes_or_no(transcript) == "no":
            conv.stage = "question"
            return listen(call, f"Okay. {QUESTION}")
        # "yes" or unclear: a person takes over. The visit is NOT changed.
        return transfer(call, "Wants to cancel")

    # Step 1: we asked "Can you make it?"
    intent = understand_reply(transcript)
    if intent == "confirm":
        conv.result = "CONFPHONE"
        return CallAnswer(
            say="Thank you, your appointment is confirmed. We look forward to seeing you. Goodbye.",
            language=call.language, action="hangup",
        )
    if intent == "cancel":
        conv.stage = "cancel_check"
        return listen(call, cancel_check_question(call), YES_NO_HINTS)
    if intent == "reschedule":
        return transfer(call, "Wants to reschedule")
    return transfer(call, "Unclear reply")


def on_no_input(call: Call) -> CallAnswer:
    conv = get_conversation(call.attempt_id)
    conv.silences += 1
    if conv.silences >= 2:
        return transfer(call, "No answer")
    if conv.stage == "cancel_check":
        return listen(call, f"Sorry, I didn't hear you. {cancel_check_question(call)}", YES_NO_HINTS)
    return listen(call, f"Sorry, I didn't hear you. {QUESTION}")