import pytest

from app.conversation.intent import cancel_choice, match_words, yes_or_no


@pytest.mark.parametrize("said, expected", [
    ("yeah we'll be there", "confirm"),
    ("Yes.", "confirm"),
    ("I need to cancel", "cancel"),
    ("I cant make it", "cancel"),
    ("I won't be there", "cancel"),
    ("can we do a different day", "reschedule"),
    ("yes but I need to reschedule", "unclear"),  # mixed -> AI or operator
    ("what?", "unclear"),
    ("I know", "unclear"),  # "know" must not count as "no"
])
def test_match_words(said, expected):
    assert match_words(said) == expected


@pytest.mark.parametrize("said, expected", [
    ("cancel it now", "cancel_now"),
    ("cancel it in any case", "cancel_now"),
    ("only if I get a new time", "new_appointment"),
    ("cancel only if you find me another appointment", "new_appointment"),  # not cancel_now
    ("keep it until I have a new one", "new_appointment"),
    ("don't cancel", "keep"),  # not cancel_now
    ("never mind I can make it", "keep"),
    ("yes", "unclear"),  # doesn't say which choice -> operator
    ("not now", "unclear"),
])
def test_cancel_choice(said, expected):
    assert cancel_choice(said) == expected


@pytest.mark.parametrize("said, expected", [
    ("yes", "yes"), ("that's right", "yes"), ("no", "no"), ("hmm", "unclear"),
])
def test_yes_or_no(said, expected):
    assert yes_or_no(said) == expected