"""No calls from 12:00 PM on Fridays and holiday eves, or on Saturdays and holidays."""
from datetime import date, datetime, time, timedelta
from functools import lru_cache
from zoneinfo import ZoneInfo

from app.rules.holidays import NOON, BlockedDay, holiday_days

CLINIC_TZ = ZoneInfo("America/New_York")  # the rules use the clinic's clock
FRIDAY, SATURDAY = 4, 5  # Python counts Monday as 0
ALL_DAY = time.min  # 00:00: blocked from the start of the day

BlockedDays = dict[date, BlockedDay]


def block_starts(day: date, blocked: BlockedDays) -> time | None:
    """When calls stop on this day: ALL_DAY, NOON, or None if it's a regular day.
    If two rules apply (a holiday on a Friday), the stricter one wins."""
    starts = []
    if day.weekday() == SATURDAY:
        starts.append(ALL_DAY)
    if day.weekday() == FRIDAY:
        starts.append(NOON)
    if day in blocked:
        starts.append(blocked[day].blocked_from or ALL_DAY)
    return min(starts) if starts else None


def can_call_now(now: datetime, blocked: BlockedDays) -> bool:
    local = now.astimezone(CLINIC_TZ)
    start = block_starts(local.date(), blocked)
    return start is None or local.time() < start


def next_block(now: datetime, blocked: BlockedDays) -> datetime:
    """The next moment calls must stop. There's a Friday in every week, so 8 days is enough."""
    local = now.astimezone(CLINIC_TZ)
    for n in range(8):
        day = local.date() + timedelta(days=n)
        start = block_starts(day, blocked)
        if start is not None:
            moment = datetime.combine(day, start, CLINIC_TZ)
            if moment > local:
                return moment
    raise RuntimeError("no block found in 8 days")  # can't happen: there's always a Friday


# ---------- Where the blocked days come from ----------
# Until B7: straight from pyluach. From B7 on: from dbo.omni_no_contact_days.

@lru_cache(maxsize=2)
def _holidays_from(today: date) -> BlockedDays:
    return {b.day: b for b in holiday_days(today, 400)}


def current_blocked_days() -> BlockedDays:
    """Worked out once a day, then reused."""
    return _holidays_from(datetime.now(CLINIC_TZ).date())