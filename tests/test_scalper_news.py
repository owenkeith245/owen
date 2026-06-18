"""Unit tests for news filter and session logic."""

import pytest
from src.scalper_logic import (
    is_nfp_window,
    is_fomc_window,
    is_active_session,
    calculate_win_rate,
    calculate_profit_factor,
    calculate_sharpe_ratio,
    get_adaptive_threshold,
)


class TestIsNFPWindow:
    def test_during_nfp(self):
        # 1st Friday, 15:30
        assert is_nfp_window(day_of_week=5, day=3, hour=15, minute=30) is True

    def test_before_nfp(self):
        # 1st Friday, 15:20 (within 15 min window)
        assert is_nfp_window(day_of_week=5, day=5, hour=15, minute=20) is True

    def test_after_nfp(self):
        # 1st Friday, 15:45 (within 15 min window)
        assert is_nfp_window(day_of_week=5, day=7, hour=15, minute=45) is True

    def test_not_friday(self):
        assert is_nfp_window(day_of_week=3, day=3, hour=15, minute=30) is False

    def test_second_friday(self):
        # day=10, not first Friday
        assert is_nfp_window(day_of_week=5, day=10, hour=15, minute=30) is False

    def test_outside_window(self):
        assert is_nfp_window(day_of_week=5, day=5, hour=14, minute=0) is False

    def test_custom_quiet_period(self):
        assert is_nfp_window(day_of_week=5, day=3, hour=15, minute=0, quiet_minutes=30) is True


class TestIsFOMCWindow:
    def test_during_fomc(self):
        # 3rd Wednesday, 21:00
        assert is_fomc_window(day_of_week=3, day=18, hour=21, minute=0) is True

    def test_before_fomc(self):
        assert is_fomc_window(day_of_week=3, day=18, hour=20, minute=50) is True

    def test_not_wednesday(self):
        assert is_fomc_window(day_of_week=4, day=18, hour=21, minute=0) is False

    def test_wrong_week(self):
        assert is_fomc_window(day_of_week=3, day=5, hour=21, minute=0) is False

    def test_outside_window(self):
        assert is_fomc_window(day_of_week=3, day=18, hour=19, minute=0) is False


class TestIsActiveSession:
    def test_london_session(self):
        assert is_active_session(hour=10) is True

    def test_ny_session(self):
        assert is_active_session(hour=16) is True

    def test_off_hours(self):
        assert is_active_session(hour=20) is False

    def test_asian_enabled(self):
        assert is_active_session(hour=4, trade_asian=True) is True

    def test_asian_disabled(self):
        assert is_active_session(hour=4, trade_asian=False) is False

    def test_london_boundary_start(self):
        assert is_active_session(hour=9) is True

    def test_london_boundary_end(self):
        assert is_active_session(hour=12) is False

    def test_custom_session_times(self):
        assert is_active_session(hour=7, london_start=7, london_end=11) is True


class TestCalculateWinRate:
    def test_all_wins(self):
        assert calculate_win_rate(10, 10) == pytest.approx(100.0)

    def test_no_trades(self):
        assert calculate_win_rate(0, 0) == 0.0

    def test_mixed(self):
        assert calculate_win_rate(7, 10) == pytest.approx(70.0)


class TestCalculateProfitFactor:
    def test_profitable(self):
        pf = calculate_profit_factor(1000.0, 500.0)
        assert pf == pytest.approx(2.0)

    def test_losing(self):
        pf = calculate_profit_factor(500.0, 1000.0)
        assert pf == pytest.approx(0.5)

    def test_no_losses(self):
        pf = calculate_profit_factor(1000.0, 0.0)
        assert pf == 999.0

    def test_breakeven(self):
        pf = calculate_profit_factor(500.0, 500.0)
        assert pf == pytest.approx(1.0)


class TestCalculateSharpeRatio:
    def test_positive_returns(self):
        returns = [1.0, 2.0, 1.5, 2.5, 1.0]
        sr = calculate_sharpe_ratio(returns)
        assert sr > 0

    def test_negative_returns(self):
        returns = [-1.0, -2.0, -1.5, -2.5, -1.0]
        sr = calculate_sharpe_ratio(returns)
        assert sr < 0

    def test_zero_returns(self):
        returns = [0.0, 0.0, 0.0]
        sr = calculate_sharpe_ratio(returns)
        assert sr == 0.0

    def test_single_return(self):
        returns = [5.0]
        sr = calculate_sharpe_ratio(returns)
        assert sr == 0.0

    def test_constant_returns(self):
        returns = [1.0] * 20
        sr = calculate_sharpe_ratio(returns)
        assert sr == 0.0  # zero std dev


class TestGetAdaptiveThreshold:
    def test_few_trades(self):
        assert get_adaptive_threshold(80.0, 70.0, 10) == 85.0

    def test_high_conf_winning(self):
        assert get_adaptive_threshold(75.0, 60.0, 100) == 85.0

    def test_med_conf_winning(self):
        assert get_adaptive_threshold(60.0, 70.0, 100) == 80.0

    def test_both_losing(self):
        assert get_adaptive_threshold(50.0, 50.0, 100) == 90.0
