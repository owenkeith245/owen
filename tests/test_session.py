"""Unit tests for session detection logic."""

import pytest
from src.titan_logic import (
    EAConfig,
    Session,
    get_current_session,
    session_to_string,
)


@pytest.fixture
def config():
    return EAConfig()


class TestGetCurrentSession:
    """Tests for GetCurrentSession() - maps hour to trading session."""

    def test_london_session_start(self, config):
        assert get_current_session(9, config) == Session.LONDON

    def test_london_session_mid(self, config):
        assert get_current_session(10, config) == Session.LONDON

    def test_london_session_end_boundary(self, config):
        # Hour 12 is NOT included (< InpLondonEnd)
        assert get_current_session(12, config) == Session.NONE

    def test_newyork_session_start(self, config):
        assert get_current_session(15, config) == Session.NEWYORK

    def test_newyork_session_mid(self, config):
        assert get_current_session(16, config) == Session.NEWYORK

    def test_newyork_session_end_boundary(self, config):
        # Hour 18 is NOT included
        assert get_current_session(18, config) == Session.NONE

    def test_no_session_early_morning(self, config):
        assert get_current_session(5, config) == Session.NONE

    def test_no_session_between_london_ny(self, config):
        assert get_current_session(13, config) == Session.NONE

    def test_no_session_late_night(self, config):
        assert get_current_session(22, config) == Session.NONE

    def test_no_session_midnight(self, config):
        assert get_current_session(0, config) == Session.NONE

    def test_custom_session_times(self):
        config = EAConfig(london_start=8, london_end=11, newyork_start=14, newyork_end=17)
        assert get_current_session(8, config) == Session.LONDON
        assert get_current_session(11, config) == Session.NONE
        assert get_current_session(14, config) == Session.NEWYORK
        assert get_current_session(17, config) == Session.NONE


class TestSessionToString:
    def test_london(self):
        assert session_to_string(Session.LONDON) == "LONDON"

    def test_newyork(self):
        assert session_to_string(Session.NEWYORK) == "NEW YORK"

    def test_none(self):
        assert session_to_string(Session.NONE) == "CLOSED"
