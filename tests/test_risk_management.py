"""Unit tests for risk management logic."""

import pytest
import math
from src.titan_logic import (
    normalize_lot,
    calculate_lot_size,
    calculate_tp,
    check_weekly_drawdown,
    should_move_sl_to_be,
    calculate_trailing_sl,
)


class TestNormalizeLot:
    """Tests for NormalizeLot() - lot size normalization."""

    def test_normal_lot(self):
        # 0.15 with step 0.01 -> stays 0.15
        result = normalize_lot(0.15, step=0.01, min_lot=0.01, max_lot=100.0)
        assert result == pytest.approx(0.15)

    def test_rounds_down_to_step(self):
        # 0.157 with step 0.01 -> 0.15
        result = normalize_lot(0.157, step=0.01, min_lot=0.01, max_lot=100.0)
        assert result == pytest.approx(0.15)

    def test_clamps_to_min_lot(self):
        result = normalize_lot(0.005, step=0.01, min_lot=0.01, max_lot=100.0)
        assert result == pytest.approx(0.01)

    def test_clamps_to_max_lot(self):
        result = normalize_lot(150.0, step=0.01, min_lot=0.01, max_lot=100.0)
        assert result == pytest.approx(100.0)

    def test_exact_step_multiple(self):
        result = normalize_lot(1.0, step=0.1, min_lot=0.1, max_lot=10.0)
        assert result == pytest.approx(1.0)

    def test_larger_step_size(self):
        # 0.35 with step 0.1 -> 0.3
        result = normalize_lot(0.35, step=0.1, min_lot=0.1, max_lot=10.0)
        assert result == pytest.approx(0.3)

    def test_zero_lot_returns_min(self):
        result = normalize_lot(0.0, step=0.01, min_lot=0.01, max_lot=100.0)
        assert result == pytest.approx(0.01)


class TestCalculateLotSize:
    """Tests for position sizing calculation."""

    def test_standard_calculation(self):
        # $10,000 balance, 1% risk, 100 point distance, $1/point
        lot = calculate_lot_size(
            balance=10000.0,
            risk_percent=1.0,
            entry=1950.0,
            stop_loss=1949.0,
            point_value=1.0,
        )
        # Risk = $100, distance = 1.0, lot = 100 / (1.0 * 1.0) = 100
        assert lot == pytest.approx(100.0)

    def test_larger_risk_percent(self):
        lot = calculate_lot_size(
            balance=10000.0,
            risk_percent=2.0,
            entry=1950.0,
            stop_loss=1940.0,
            point_value=1.0,
        )
        # Risk = $200, distance = 10.0, lot = 200 / (10 * 1) = 20
        assert lot == pytest.approx(20.0)

    def test_zero_distance_returns_zero(self):
        lot = calculate_lot_size(
            balance=10000.0,
            risk_percent=1.0,
            entry=1950.0,
            stop_loss=1950.0,  # Same as entry
            point_value=1.0,
        )
        assert lot == 0.0

    def test_zero_point_value_returns_zero(self):
        lot = calculate_lot_size(
            balance=10000.0,
            risk_percent=1.0,
            entry=1950.0,
            stop_loss=1940.0,
            point_value=0.0,
        )
        assert lot == 0.0

    def test_sell_trade_distance(self):
        # Entry below stop for a sell
        lot = calculate_lot_size(
            balance=5000.0,
            risk_percent=1.0,
            entry=1950.0,
            stop_loss=1960.0,  # SL above entry for sell
            point_value=1.0,
        )
        # Risk = $50, distance = 10, lot = 50 / 10 = 5
        assert lot == pytest.approx(5.0)


class TestCalculateTP:
    """Tests for take-profit calculation."""

    def test_buy_trade_tp(self):
        tp = calculate_tp(entry=1950.0, stop_loss=1940.0, rr_ratio=2.0, is_buy=True)
        # Risk = 10, TP = 1950 + 10*2 = 1970
        assert tp == pytest.approx(1970.0)

    def test_sell_trade_tp(self):
        tp = calculate_tp(entry=1950.0, stop_loss=1960.0, rr_ratio=2.0, is_buy=False)
        # Risk = 10, TP = 1950 - 10*2 = 1930
        assert tp == pytest.approx(1930.0)

    def test_rr_ratio_3(self):
        tp = calculate_tp(entry=2000.0, stop_loss=1990.0, rr_ratio=3.0, is_buy=True)
        assert tp == pytest.approx(2030.0)

    def test_rr_ratio_1(self):
        tp = calculate_tp(entry=2000.0, stop_loss=2010.0, rr_ratio=1.0, is_buy=False)
        assert tp == pytest.approx(1990.0)


class TestCheckWeeklyDrawdown:
    """Tests for weekly drawdown halt logic."""

    def test_no_drawdown(self):
        assert check_weekly_drawdown(10000.0, 10000.0, 5.0) is False

    def test_within_limit(self):
        # 3% drawdown, limit is 5%
        assert check_weekly_drawdown(10000.0, 9700.0, 5.0) is False

    def test_exceeds_limit(self):
        # 6% drawdown, limit is 5%
        assert check_weekly_drawdown(10000.0, 9400.0, 5.0) is True

    def test_exactly_at_limit(self):
        # 5% exactly - not exceeded (must be > threshold)
        assert check_weekly_drawdown(10000.0, 9500.0, 5.0) is False

    def test_zero_start_balance(self):
        assert check_weekly_drawdown(0.0, 9000.0, 5.0) is False

    def test_profit_no_halt(self):
        # Balance grew - negative drawdown
        assert check_weekly_drawdown(10000.0, 11000.0, 5.0) is False


class TestShouldMoveSLToBE:
    """Tests for breakeven stop loss logic."""

    def test_buy_should_move(self):
        # profitR >= trail_start and sl < entry for buy
        assert should_move_sl_to_be(
            profit_r=1.5, trail_start_r=1.0, sl=1940.0, entry=1950.0, is_buy=True
        ) is True

    def test_buy_not_enough_profit(self):
        assert should_move_sl_to_be(
            profit_r=0.5, trail_start_r=1.0, sl=1940.0, entry=1950.0, is_buy=True
        ) is False

    def test_buy_sl_already_at_be(self):
        # sl >= entry already
        assert should_move_sl_to_be(
            profit_r=1.5, trail_start_r=1.0, sl=1950.0, entry=1950.0, is_buy=True
        ) is False

    def test_sell_should_move(self):
        # sl > entry for sell means SL hasn't been moved yet
        assert should_move_sl_to_be(
            profit_r=1.2, trail_start_r=1.0, sl=1960.0, entry=1950.0, is_buy=False
        ) is True

    def test_sell_sl_already_at_be(self):
        assert should_move_sl_to_be(
            profit_r=1.5, trail_start_r=1.0, sl=1950.0, entry=1950.0, is_buy=False
        ) is False


class TestCalculateTrailingSL:
    """Tests for trailing stop loss calculation."""

    def test_buy_trail_moves_up(self):
        new_sl = calculate_trailing_sl(
            current_price=1970.0, current_sl=1955.0, atr=10.0, is_buy=True
        )
        # trail_dist = 5.0, new_sl = 1970 - 5 = 1965, which > 1955
        assert new_sl == pytest.approx(1965.0)

    def test_buy_trail_no_move_down(self):
        new_sl = calculate_trailing_sl(
            current_price=1958.0, current_sl=1955.0, atr=10.0, is_buy=True
        )
        # new_sl = 1958 - 5 = 1953, which < 1955, so keep current
        assert new_sl == pytest.approx(1955.0)

    def test_sell_trail_moves_down(self):
        new_sl = calculate_trailing_sl(
            current_price=1930.0, current_sl=1945.0, atr=10.0, is_buy=False
        )
        # trail_dist = 5.0, new_sl = 1930 + 5 = 1935, which < 1945
        assert new_sl == pytest.approx(1935.0)

    def test_sell_trail_no_move_up(self):
        new_sl = calculate_trailing_sl(
            current_price=1942.0, current_sl=1945.0, atr=10.0, is_buy=False
        )
        # new_sl = 1942 + 5 = 1947, which > 1945, so keep current
        assert new_sl == pytest.approx(1945.0)

    def test_large_atr_wider_trail(self):
        new_sl = calculate_trailing_sl(
            current_price=1980.0, current_sl=1950.0, atr=40.0, is_buy=True
        )
        # trail_dist = 20, new_sl = 1980 - 20 = 1960
        assert new_sl == pytest.approx(1960.0)
