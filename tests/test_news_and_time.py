"""Unit tests for news filter, time utilities, and string converters."""

import pytest
from src.titan_logic import (
    Bias,
    Session,
    is_news_event,
    get_monday_midnight,
    bias_to_string,
    session_to_string,
)


class TestIsNewsEvent:
    """Tests for IsNewsEvent() - NFP news event filter."""

    def test_nfp_friday_first_week_during_event(self):
        # First Friday (day <= 7), hour=15, min within quiet window
        assert is_news_event(day_of_week=5, day=3, hour=15, minute=30) is True

    def test_nfp_friday_before_event(self):
        # 15 minutes before NFP (30-15=15)
        assert is_news_event(day_of_week=5, day=7, hour=15, minute=15) is True

    def test_nfp_friday_after_event(self):
        # 15 minutes after NFP (30+15=45)
        assert is_news_event(day_of_week=5, day=5, hour=15, minute=45) is True

    def test_not_friday(self):
        # Monday at same time
        assert is_news_event(day_of_week=1, day=3, hour=15, minute=30) is False

    def test_friday_second_week(self):
        # Friday but day > 7 (not first Friday)
        assert is_news_event(day_of_week=5, day=10, hour=15, minute=30) is False

    def test_friday_wrong_hour(self):
        assert is_news_event(day_of_week=5, day=3, hour=14, minute=30) is False

    def test_friday_outside_quiet_window(self):
        # minute = 50 > 30+15=45
        assert is_news_event(day_of_week=5, day=3, hour=15, minute=50) is False

    def test_friday_before_quiet_window(self):
        # minute = 10 < 30-15=15
        assert is_news_event(day_of_week=5, day=3, hour=15, minute=10) is False

    def test_custom_quiet_minutes(self):
        # 30 minutes quiet window: 30-30=0 to 30+30=60
        assert is_news_event(day_of_week=5, day=3, hour=15, minute=5, quiet_minutes=30) is True

    def test_edge_quiet_start(self):
        # Exactly at quiet_start (30-15=15)
        assert is_news_event(day_of_week=5, day=3, hour=15, minute=15) is True

    def test_edge_quiet_end(self):
        # Exactly at quiet_end (30+15=45)
        assert is_news_event(day_of_week=5, day=3, hour=15, minute=45) is True


class TestGetMondayMidnight:
    """Tests for GetMondayMidnight() - week start calculation."""

    def test_on_monday(self):
        # Monday 10:30:00, timestamp = arbitrary
        # days_since_monday = 0
        ts = 1718000000  # arbitrary
        result = get_monday_midnight(day_of_week=1, timestamp=ts, hour=10, minute=30, sec=0)
        expected = ts - 0 * 86400 - 10 * 3600 - 30 * 60 - 0
        assert result == expected

    def test_on_wednesday(self):
        # Wednesday: days_since_monday = 2
        ts = 1718200000
        result = get_monday_midnight(day_of_week=3, timestamp=ts, hour=14, minute=0, sec=0)
        expected = ts - 2 * 86400 - 14 * 3600 - 0 * 60 - 0
        assert result == expected

    def test_on_sunday(self):
        # Sunday: days_since_monday = 6
        ts = 1718500000
        result = get_monday_midnight(day_of_week=0, timestamp=ts, hour=8, minute=15, sec=30)
        expected = ts - 6 * 86400 - 8 * 3600 - 15 * 60 - 30
        assert result == expected

    def test_on_friday(self):
        # Friday: days_since_monday = 4
        ts = 1718400000
        result = get_monday_midnight(day_of_week=5, timestamp=ts, hour=16, minute=45, sec=10)
        expected = ts - 4 * 86400 - 16 * 3600 - 45 * 60 - 10
        assert result == expected

    def test_on_saturday(self):
        # Saturday: days_since_monday = 5
        ts = 1718450000
        result = get_monday_midnight(day_of_week=6, timestamp=ts, hour=0, minute=0, sec=0)
        expected = ts - 5 * 86400
        assert result == expected


class TestBiasToString:
    """Tests for BiasToString() - enum display conversion."""

    def test_bullish(self):
        assert bias_to_string(Bias.BULLISH) == "BULLISH"

    def test_bearish(self):
        assert bias_to_string(Bias.BEARISH) == "BEARISH"

    def test_neutral(self):
        assert bias_to_string(Bias.NEUTRAL) == "NEUTRAL"


class TestSessionToString:
    def test_london(self):
        assert session_to_string(Session.LONDON) == "LONDON"

    def test_newyork(self):
        assert session_to_string(Session.NEWYORK) == "NEW YORK"

    def test_none(self):
        assert session_to_string(Session.NONE) == "CLOSED"
