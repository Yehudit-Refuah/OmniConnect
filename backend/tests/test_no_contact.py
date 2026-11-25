from datetime import date, datetime

import pytest

from app.rules.holidays import holiday_days
from app.rules.no_contact import CLINIC_TZ, can_call_now, next_block

HOLIDAYS_2027 = {b.day: b for b in holiday_days(date(2027, 1, 1), 365)}


def at(year, month, day, hour, minute=0) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=CLINIC_TZ)


@pytest.mark.parametrize("now, allowed", [
    (at(2027, 1, 8, 11, 59), True),   # Friday 11:59 AM
    (at(2027, 1, 8, 12, 0), False),   # Friday 12:00 PM
    (at(2027, 1, 9, 10, 0), False),   # Saturday
    (at(2027, 1, 10, 9, 0), True),    # Sunday morning
    (at(2027, 1, 12, 15, 0), True),   # regular Tuesday afternoon
    (at(2027, 4, 21, 11, 59), True),  # Erev Pesach (Wednesday), before noon
    (at(2027, 4, 21, 12, 0), False),  # Erev Pesach, from noon
    (at(2027, 4, 22, 9, 0), False),   # Pesach (Thursday), all day
    (at(2027, 4, 23, 9, 0), False),   # Pesach II on a Friday: all day, not just from noon
    (at(2027, 4, 25, 10, 0), True),   # Chol Hamoed (Sunday)
])
def test_can_call_now(now, allowed):
    assert can_call_now(now, HOLIDAYS_2027) == allowed


def test_next_block_is_noon_on_erev_pesach():
    assert next_block(at(2027, 4, 21, 9, 0), HOLIDAYS_2027) == at(2027, 4, 21, 12, 0)


def test_next_block_on_a_regular_monday_is_friday_noon():
    assert next_block(at(2027, 1, 11, 9, 0), HOLIDAYS_2027) == at(2027, 1, 15, 12, 0)