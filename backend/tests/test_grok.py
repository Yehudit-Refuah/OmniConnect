from app.conversation import intent


def test_ai_off_means_grok_is_not_asked(monkeypatch):
    monkeypatch.setenv("INTENT_AI_PROVIDER", "off")

    def must_not_be_called(transcript):
        raise AssertionError("Grok must not be asked when the AI is off")

    monkeypatch.setattr(intent, "ask_grok", must_not_be_called)
    assert intent.understand_reply("um, I think so") == "unclear"


def test_grok_error_means_unclear(monkeypatch):
    def broken_client():
        raise RuntimeError("no network")

    monkeypatch.setattr(intent, "grok_client", broken_client)
    assert intent.ask_grok("um, I think so") == "unclear"