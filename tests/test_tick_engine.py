"""Unit tests for tick engine logic."""

import pytest
from src.scalper_logic import (
    calculate_order_flow,
    calculate_tick_volatility,
    is_spread_normal,
)


class TestCalculateOrderFlow:
    def test_balanced_flow(self):
        buy, sell, net = calculate_order_flow(50, 50)
        assert buy == pytest.approx(0.5)
        assert sell == pytest.approx(0.5)
        assert net == pytest.approx(0.0)

    def test_strong_buy_pressure(self):
        buy, sell, net = calculate_order_flow(80, 20)
        assert buy == pytest.approx(0.8)
        assert sell == pytest.approx(0.2)
        assert net == pytest.approx(0.6)

    def test_strong_sell_pressure(self):
        buy, sell, net = calculate_order_flow(10, 90)
        assert buy == pytest.approx(0.1)
        assert sell == pytest.approx(0.9)
        assert net == pytest.approx(-0.8)

    def test_zero_ticks(self):
        buy, sell, net = calculate_order_flow(0, 0)
        assert buy == 0.0
        assert sell == 0.0
        assert net == 0.0

    def test_all_upticks(self):
        buy, sell, net = calculate_order_flow(100, 0)
        assert buy == pytest.approx(1.0)
        assert net == pytest.approx(1.0)


class TestCalculateTickVolatility:
    def test_low_volatility(self):
        changes = [0.01, -0.01, 0.01, -0.01] * 10
        vol = calculate_tick_volatility(changes)
        assert vol == pytest.approx(0.01, abs=0.001)

    def test_high_volatility(self):
        changes = [1.0, -1.0, 1.5, -1.5, 2.0, -2.0] * 10
        vol = calculate_tick_volatility(changes)
        assert vol > 1.0

    def test_zero_changes(self):
        changes = [0.0] * 20
        vol = calculate_tick_volatility(changes)
        assert vol == 0.0

    def test_insufficient_data(self):
        changes = [0.1, 0.2, 0.3]
        vol = calculate_tick_volatility(changes)
        assert vol == 0.0

    def test_constant_positive(self):
        changes = [0.5] * 50
        vol = calculate_tick_volatility(changes)
        assert vol == pytest.approx(0.0, abs=0.001)


class TestIsSpreadNormal:
    def test_normal_spread(self):
        assert is_spread_normal(15.0, 12.0) is True

    def test_wide_spread(self):
        assert is_spread_normal(30.0, 12.0) is False

    def test_exactly_at_limit(self):
        # ratio = 2.0 -> NOT < 2.0 so it's False
        assert is_spread_normal(24.0, 12.0) is False

    def test_tight_spread(self):
        assert is_spread_normal(8.0, 12.0) is True

    def test_zero_avg_spread(self):
        assert is_spread_normal(10.0, 0.0) is True

    def test_custom_ratio(self):
        assert is_spread_normal(30.0, 12.0, max_ratio=3.0) is True
