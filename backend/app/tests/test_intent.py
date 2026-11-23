import pytest

from app.conversation.intent import match_words, yes_or_no


@pytest.mark.parametrize("said, expected", [
    ("yeah we'll be there", "confirm"),
    ("Yes.", "confirm"),
    ("I need to cancel", "cancel"),
    ("I cant make it", "cancel"),
    ("I won't be there", "cancel"),
    ("can we do a different day", "reschedule"),
    ("yes but I need to reschedule", "unclear"),  # mixed -> Claude or operator
    ("what?", "unclear"),
    ("I know", "unclear"),  # "know" must not count as "no"
])
def test_match_words(said, expected):
    assert match_words(said) == expected


@pytest.mark.parametrize("said, expected", [
    ("yes", "yes"), ("that's right", "yes"), ("no", "no"), ("hmm", "unclear"),
])
def test_yes_or_no(said, expected):
    assert yes_or_no(said) == expected