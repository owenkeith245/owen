"""Unit tests for position management logic."""

import pytest
from src.scalper_logic import (
    TradeState,
    calculate_profit_r,
    should_move_to_breakeven,
    calculate_trailing_stop,
    calculate_partial_close_volume,
    calculate_take_profit,
)


class TestCalculateProfitR:
    def test_buy_in_profit(self):
        r = calculate_profit_r(entry=2000.0, current_price=2010.0, stop_loss=1995.0, is_buy=True)
        assert r == pytest.approx(2.0)

    def test_buy_at_loss(self):
        r = calculate_profit_r(entry=2000.0, current_price=1995.0, stop_loss=1995.0, is_buy=True)
        assert r == pytest.approx(-1.0)

    def test_sell_in_profit(self):
        r = calculate_profit_r(entry=2000.0, current_price=1990.0, stop_loss=2005.0, is_buy=False)
        assert r == pytest.approx(2.0)

    def test_sell_at_loss(self):
        r = calculate_profit_r(entry=2000.0, current_price=2005.0, stop_loss=2005.0, is_buy=False)
        assert r == pytest.approx(-1.0)

    def test_zero_risk_returns_zero(self):
        r = calculate_profit_r(entry=2000.0, current_price=2010.0, stop_loss=2000.0, is_buy=True)
        assert r == 0.0

    def test_buy_breakeven(self):
        r = calculate_profit_r(entry=2000.0, current_price=2000.0, stop_loss=1995.0, is_buy=True)
        assert r == pytest.approx(0.0)


class TestShouldMoveToBreakeven:
    def test_buy_eligible(self):
        result = should_move_to_breakeven(profit_r=1.5, break_even_r=1.0, sl=1995.0, entry=2000.0, is_buy=True)
        assert result is True

    def test_buy_not_enough_profit(self):
        result = should_move_to_breakeven(profit_r=0.5, break_even_r=1.0, sl=1995.0, entry=2000.0, is_buy=True)
        assert result is False

    def test_buy_already_at_be(self):
        result = should_move_to_breakeven(profit_r=1.5, break_even_r=1.0, sl=2000.0, entry=2000.0, is_buy=True)
        assert result is False

    def test_sell_eligible(self):
        result = should_move_to_breakeven(profit_r=1.2, break_even_r=1.0, sl=2005.0, entry=2000.0, is_buy=False)
        assert result is True

    def test_sell_already_at_be(self):
        result = should_move_to_breakeven(profit_r=1.5, break_even_r=1.0, sl=2000.0, entry=2000.0, is_buy=False)
        assert result is False


class TestCalculateTrailingStop:
    def test_buy_trail_up(self):
        new_sl = calculate_trailing_stop(current_price=2020.0, current_sl=2005.0, atr=5.0, trail_mult=0.5, is_buy=True)
        # new_sl = 2020 - 2.5 = 2017.5 > 2005 -> moves
        assert new_sl == pytest.approx(2017.5)

    def test_buy_no_move(self):
        new_sl = calculate_trailing_stop(current_price=2008.0, current_sl=2010.0, atr=5.0, trail_mult=0.5, is_buy=True)
        # new_sl = 2008 - 2.5 = 2005.5 < 2010 -> no move
        assert new_sl == pytest.approx(2010.0)

    def test_sell_trail_down(self):
        new_sl = calculate_trailing_stop(current_price=1980.0, current_sl=1995.0, atr=5.0, trail_mult=0.5, is_buy=False)
        # new_sl = 1980 + 2.5 = 1982.5 < 1995 -> moves
        assert new_sl == pytest.approx(1982.5)

    def test_sell_no_move(self):
        new_sl = calculate_trailing_stop(current_price=1992.0, current_sl=1990.0, atr=5.0, trail_mult=0.5, is_buy=False)
        # new_sl = 1992 + 2.5 = 1994.5 > 1990 -> no move
        assert new_sl == pytest.approx(1990.0)


class TestCalculatePartialCloseVolume:
    def test_normal_partial(self):
        vol = calculate_partial_close_volume(initial_lots=1.0, close_percent=0.4, lot_step=0.01, lot_min=0.01)
        assert vol == pytest.approx(0.40)

    def test_rounds_down(self):
        vol = calculate_partial_close_volume(initial_lots=0.33, close_percent=0.4, lot_step=0.01, lot_min=0.01)
        # 0.33 * 0.4 = 0.132 -> floor to 0.13
        assert vol == pytest.approx(0.13)

    def test_below_minimum(self):
        vol = calculate_partial_close_volume(initial_lots=0.01, close_percent=0.4, lot_step=0.01, lot_min=0.01)
        # 0.01 * 0.4 = 0.004 -> floor to 0.0 < 0.01 -> returns 0
        assert vol == 0.0

    def test_large_lots(self):
        vol = calculate_partial_close_volume(initial_lots=5.0, close_percent=0.3, lot_step=0.01, lot_min=0.01)
        assert vol == pytest.approx(1.50)


class TestCalculateTakeProfit:
    def test_buy_tp1(self):
        tp = calculate_take_profit(entry=2000.0, stop_loss=1995.0, rr_ratio=2.0, is_buy=True)
        # risk = 5, tp = 2000 + 10 = 2010
        assert tp == pytest.approx(2010.0)

    def test_buy_tp3(self):
        tp = calculate_take_profit(entry=2000.0, stop_loss=1995.0, rr_ratio=5.0, is_buy=True)
        assert tp == pytest.approx(2025.0)

    def test_sell_tp1(self):
        tp = calculate_take_profit(entry=2000.0, stop_loss=2005.0, rr_ratio=2.0, is_buy=False)
        # risk = 5, tp = 2000 - 10 = 1990
        assert tp == pytest.approx(1990.0)

    def test_sell_tp3(self):
        tp = calculate_take_profit(entry=2000.0, stop_loss=2005.0, rr_ratio=5.0, is_buy=False)
        assert tp == pytest.approx(1975.0)

    def test_asymmetric_risk(self):
        tp = calculate_take_profit(entry=2000.0, stop_loss=1990.0, rr_ratio=3.0, is_buy=True)
        assert tp == pytest.approx(2030.0)
