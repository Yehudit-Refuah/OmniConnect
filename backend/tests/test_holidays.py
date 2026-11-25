from datetime import date

from app.rules.holidays import NOON, BlockedDay, holiday_days


def blocked_2027() -> dict[date, BlockedDay]:
    return {b.day: b for b in holiday_days(date(2027, 1, 1), days=365)}


def test_eve_is_blocked_from_noon():
    assert blocked_2027()[date(2027, 4, 21)] == BlockedDay(date(2027, 4, 21), NOON, "Erev Pesach")


def test_second_day_counts_outside_israel():
    assert blocked_2027()[date(2027, 4, 23)].blocked_from is None  # Pesach II


def test_chol_hamoed_and_purim_are_not_blocked():
    days = blocked_2027()
    assert date(2027, 4, 25) not in days  # Chol Hamoed Pesach
    assert date(2027, 3, 23) not in days  # Purim


def test_twenty_days_in_2027():
    assert len(blocked_2027()) == 20