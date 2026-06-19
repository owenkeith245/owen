"""Unit tests for risk management logic."""

import pytest
from src.scalper_logic import (
    RiskConfig,
    RiskState,
    can_trade,
    allocate_risk,
    check_weekly_drawdown,
    check_emergency_drawdown,
)


class TestCanTrade:
    def test_can_trade_normal(self):
        state = RiskState(daily_risk_budget=200.0, daily_risk_used=50.0)
        config = RiskConfig()
        assert can_trade(state, config) is True

    def test_halt_daily(self):
        state = RiskState(halt_daily=True, daily_risk_budget=200.0)
        assert can_trade(state, RiskConfig()) is False

    def test_halt_weekly(self):
        state = RiskState(halt_weekly=True, daily_risk_budget=200.0)
        assert can_trade(state, RiskConfig()) is False

    def test_halt_emergency(self):
        state = RiskState(halt_emergency=True, daily_risk_budget=200.0)
        assert can_trade(state, RiskConfig()) is False

    def test_halt_consecutive(self):
        state = RiskState(halt_consecutive=True, daily_risk_budget=200.0)
        assert can_trade(state, RiskConfig()) is False

    def test_max_trades_reached(self):
        state = RiskState(open_trade_count=10, daily_risk_budget=200.0)
        config = RiskConfig(max_open_trades=10)
        assert can_trade(state, config) is False

    def test_risk_budget_exhausted(self):
        state = RiskState(daily_risk_used=200.0, daily_risk_budget=200.0)
        assert can_trade(state, RiskConfig()) is False

    def test_just_under_budget(self):
        state = RiskState(daily_risk_used=199.0, daily_risk_budget=200.0, open_trade_count=3)
        config = RiskConfig(max_open_trades=5)
        assert can_trade(state, config) is True


class TestAllocateRisk:
    def test_normal_allocation(self):
        config = RiskConfig(max_single_trade_risk=0.5)
        state = RiskState(daily_risk_budget=200.0, daily_risk_used=0.0)
        approved, lots, risk, reason = allocate_risk(
            balance=10000.0, config=config, state=state,
            stop_loss_points=20.0, point_value=1.0,
            confidence=90.0
        )
        assert approved is True
        assert lots > 0
        assert risk > 0
        assert reason == ""

    def test_confidence_scales_risk(self):
        config = RiskConfig(max_single_trade_risk=1.0)
        state = RiskState(daily_risk_budget=200.0, daily_risk_used=0.0)
        
        _, _, risk_high, _ = allocate_risk(
            balance=10000.0, config=config, state=state,
            stop_loss_points=20.0, point_value=1.0, confidence=100.0
        )
        _, _, risk_low, _ = allocate_risk(
            balance=10000.0, config=config, state=state,
            stop_loss_points=20.0, point_value=1.0, confidence=50.0
        )
        assert risk_high > risk_low

    def test_rejected_when_halted(self):
        config = RiskConfig()
        state = RiskState(halt_daily=True, daily_risk_budget=200.0)
        approved, lots, risk, reason = allocate_risk(
            balance=10000.0, config=config, state=state,
            stop_loss_points=20.0, point_value=1.0, confidence=90.0
        )
        assert approved is False
        assert reason == "HALTED"

    def test_invalid_stop_loss(self):
        config = RiskConfig()
        state = RiskState(daily_risk_budget=200.0)
        approved, _, _, reason = allocate_risk(
            balance=10000.0, config=config, state=state,
            stop_loss_points=0.0, point_value=1.0, confidence=90.0
        )
        assert approved is False
        assert reason == "INVALID SL"

    def test_lot_too_small(self):
        config = RiskConfig(max_single_trade_risk=0.001)
        state = RiskState(daily_risk_budget=200.0)
        approved, _, _, reason = allocate_risk(
            balance=100.0, config=config, state=state,
            stop_loss_points=1000.0, point_value=10.0, confidence=10.0,
            lot_min=0.01
        )
        assert approved is False
        assert reason == "LOT TOO SMALL"

    def test_limited_by_available_budget(self):
        config = RiskConfig(max_single_trade_risk=1.0)
        state = RiskState(daily_risk_budget=200.0, daily_risk_used=195.0)
        approved, lots, risk, _ = allocate_risk(
            balance=10000.0, config=config, state=state,
            stop_loss_points=20.0, point_value=1.0, confidence=100.0
        )
        assert approved is True
        assert risk <= 5.0  # only $5 remaining


class TestWeeklyDrawdown:
    def test_no_drawdown(self):
        assert check_weekly_drawdown(10000.0, 10500.0, 5.0) is False

    def test_within_limit(self):
        assert check_weekly_drawdown(10000.0, 9600.0, 5.0) is False

    def test_exceeds_limit(self):
        assert check_weekly_drawdown(10000.0, 9400.0, 5.0) is True

    def test_exactly_at_limit(self):
        assert check_weekly_drawdown(10000.0, 9500.0, 5.0) is False

    def test_zero_start_balance(self):
        assert check_weekly_drawdown(0.0, 9000.0, 5.0) is False


class TestEmergencyDrawdown:
    def test_no_drawdown(self):
        assert check_emergency_drawdown(10000.0, 10200.0, 5.0) is False

    def test_exceeds_emergency(self):
        assert check_emergency_drawdown(10000.0, 9400.0, 5.0) is True

    def test_within_limit(self):
        assert check_emergency_drawdown(10000.0, 9600.0, 5.0) is False

    def test_zero_balance(self):
        assert check_emergency_drawdown(0.0, 5000.0, 5.0) is False
