from datetime import datetime
from typing import Literal

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

# ---------- POST /calls: what the PBX sends us ----------

class TransferInfo(BaseModel):
    extension: str
    queue_wait_seconds: int | None = None
    answered_by_extension: str | None = None
    result: str | None = None  # "answered" or "abandoned"


class CallEvent(BaseModel):
    attempt_id: str
    sequence: int
    event: Literal["dialing", "answered", "voicemail", "reply",
                   "no_input", "hangup_by_patient", "ended"]
    occurred_at: datetime
    # only for "reply"
    transcript: str | None = None
    transcript_confidence: float | None = None
    # only for "ended"
    outcome: str | None = None
    dial_started_at: datetime | None = None
    answered_at: datetime | None = None
    transfer: TransferInfo | None = None
    recording_id: str | None = None
    detail: str | None = None


# ---------- POST /calls: what we answer ----------

class ListenSettings(BaseModel):
    max_silence_seconds: int = 5
    max_speech_seconds: int = 15
    hints: list[str] = []


class CallAnswer(BaseModel):
    say: str = ""
    language: str = "en-US"
    action: Literal["dial", "skip", "listen", "hangup", "transfer", "none"]
    listen: ListenSettings | None = None
    transfer_to: str | None = None
    transfer_note: str | None = None
    reason: str | None = None
