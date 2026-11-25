"""Jewish holidays that block calls, worked out by the pyluach library.

No one types dates: the app asks pyluach. Outside Israel, so second days count.
Blocked: Yom Tov and Yom Kippur all day, and the eve of each one from 12:00 PM.
Not blocked: Chol Hamoed, Purim, Chanukah, fast days.
"""
from datetime import date, time, timedelta
from typing import NamedTuple

from pyluach import dates

NOON = time(12, 0)


class BlockedDay(NamedTuple):
    day: date
    blocked_from: time | None  # None = blocked all day, NOON = an eve
    reason: str


def yom_tov(day: date) -> str | None:
    """The holiday name if calls are blocked all day, else None."""
    return dates.GregorianDate.from_pydate(day).to_heb().festival(
        israel=False, include_working_days=False
    )


def holiday_days(start: date, days: int = 400) -> list[BlockedDay]:
    """Every blocked holiday day and eve from start, for the next `days` days.
    Plain Fridays and Saturdays are not listed: the no-contact check handles them."""
    found = []
    for n in range(days):
        day = start + timedelta(days=n)
        name = yom_tov(day)
        tomorrow = yom_tov(day + timedelta(days=1))
        if name:
            found.append(BlockedDay(day, None, name))
        elif tomorrow:
            found.append(BlockedDay(day, NOON, f"Erev {tomorrow}"))
    return found