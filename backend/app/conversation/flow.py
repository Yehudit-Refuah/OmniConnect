"""Decide what to say and do next in the conversation."""

from dataclasses import dataclass
from datetime import datetime

from app.conversation.intent import cancel_choice, understand_reply, yes_or_no
from app.pbx.models import Call, CallAnswer, ListenSettings

QUESTION = "Can you make it? Please say confirm, cancel, or reschedule."
MAIN_HINTS = ["confirm", "cancel", "reschedule", "yes", "no"]
CANCEL_HINTS = ["cancel now", "new appointment", "keep it"]
YES_NO_HINTS = ["yes", "no"]


@dataclass
class Conversation:
    """Where one call is in the conversation."""
    stage: str = "question"  # "question", "cancel_choice" or "cancel_confirm"
    silences: int = 0
    result: str | None = None  # "CONFPHONE" (confirmed) or "CANCPHONE" (cancelled)

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


def appointment_count(call: Call) -> int:
    return sum(len(p.appointments) for p in call.patients)


def first_visit_time(call: Call) -> str:
    return spoken_time(call.patients[0].appointments[0].visit_datetime)


def cancel_choice_question(call: Call) -> str:
    """Asked once the patient says they want to cancel (one appointment only)."""
    return (f"You'd like to cancel your appointment on {first_visit_time(call)}. "
            "Should we cancel it now, or only once you have a new appointment? "
            "Please say cancel now, or new appointment.")


def cancel_confirm_question(call: Call) -> str:
    """Asked once more before we really cancel."""
    return (f"Just to make sure: you want to cancel your appointment on {first_visit_time(call)}. "
            "Is that right? Please say yes or no.")

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

    # Step 3: we asked "Just to make sure: you want to cancel…? Is that right?"
    if conv.stage == "cancel_confirm":
        answer = yes_or_no(transcript)
        if answer == "yes":
            conv.result = "CANCPHONE"
            return CallAnswer(
                say=(f"Your appointment on {first_visit_time(call)} has been cancelled. "
                     "Thank you for letting us know. Goodbye."),
                language=call.language, action="hangup",
            )
        if answer == "no":
            return transfer(call, "Said no when asked to confirm the cancel")
        return transfer(call, "Wants to cancel, unclear at the final check")

    # Step 2: we asked "Should we cancel it now, or only once you have a new appointment?"
    if conv.stage == "cancel_choice":
        choice = cancel_choice(transcript)
        if choice == "cancel_now":
            conv.stage = "cancel_confirm"
            return listen(call, cancel_confirm_question(call), YES_NO_HINTS)
        if choice == "new_appointment":
            # The visit is NOT changed. Staff find a new time first, then cancel the old one.
            return transfer(call, "Cancel once a new appointment is booked")
        if choice == "keep":
            conv.stage = "question"
            return listen(call, f"Okay, we won't cancel it. {QUESTION}")
        return transfer(call, "Wants to cancel, choice unclear")

    # Step 1: we asked "Can you make it?"
    intent = understand_reply(transcript)
    if intent == "confirm":
        conv.result = "CONFPHONE"
        return CallAnswer(
            say="Thank you, your appointment is confirmed. We look forward to seeing you. Goodbye.",
            language=call.language, action="hangup",
        )
    if intent == "cancel":
        if appointment_count(call) > 1:
            # Several appointments on one call: a person sorts out which ones.
            return transfer(call, "Wants to cancel (several appointments)")
        conv.stage = "cancel_choice"
        return listen(call, cancel_choice_question(call), CANCEL_HINTS)
    if intent == "reschedule":
        return transfer(call, "Wants to reschedule")
    return transfer(call, "Unclear reply")


def on_no_input(call: Call) -> CallAnswer:
    conv = get_conversation(call.attempt_id)
    conv.silences += 1
    if conv.silences >= 2:
        return transfer(call, "No answer")
    if conv.stage == "cancel_choice":
        return listen(call, f"Sorry, I didn't hear you. {cancel_choice_question(call)}", CANCEL_HINTS)
    if conv.stage == "cancel_confirm":
        return listen(call, f"Sorry, I didn't hear you. {cancel_confirm_question(call)}", YES_NO_HINTS)
    return listen(call, f"Sorry, I didn't hear you. {QUESTION}")