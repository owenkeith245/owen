"""Unit tests for the scoring/confluence engine."""

import pytest
from src.titan_logic import (
    Bias,
    EAConfig,
    Session,
    SetupInfo,
    calculate_score,
    should_execute_trade,
)


@pytest.fixture
def config():
    return EAConfig()


class TestCalculateScore:
    """Tests for CalculateScore() - confluence score calculation."""

    def test_zero_score_no_signals(self, config):
        # Set different biases to avoid trend alignment score
        setup = SetupInfo(bias_h4=Bias.BULLISH, bias_h1=Bias.BEARISH)
        assert calculate_score(setup, config) == 0

    def test_full_bullish_score(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BULLISH,
            bias_h1=Bias.BULLISH,
            session=Session.LONDON,
            liq_sweep_bull=True,
            mss_bull=True,
            bos_bull=True,
            fvg_bull=True,
            displacement_bull=True,
            volatility_active=True,
        )
        expected = (
            config.score_liquidity
            + config.score_mss
            + config.score_bos
            + config.score_fvg
            + config.score_displacement
            + config.score_volatility
            + config.score_session
            + config.score_trend
        )
        assert calculate_score(setup, config) == expected
        assert expected == 100  # All weights sum to 100

    def test_full_bearish_score(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BEARISH,
            bias_h1=Bias.BEARISH,
            session=Session.NEWYORK,
            liq_sweep_bear=True,
            mss_bear=True,
            bos_bear=True,
            fvg_bear=True,
            displacement_bear=True,
            volatility_active=True,
        )
        expected = (
            config.score_liquidity
            + config.score_mss
            + config.score_bos
            + config.score_fvg
            + config.score_displacement
            + config.score_volatility
            + config.score_session
            + config.score_trend
        )
        assert calculate_score(setup, config) == expected

    def test_liquidity_only_bullish(self, config):
        setup = SetupInfo(bias_h4=Bias.BULLISH, liq_sweep_bull=True)
        assert calculate_score(setup, config) == config.score_liquidity

    def test_liquidity_only_bearish(self, config):
        setup = SetupInfo(bias_h4=Bias.BEARISH, liq_sweep_bear=True)
        assert calculate_score(setup, config) == config.score_liquidity

    def test_liquidity_wrong_direction_no_score(self, config):
        # Bullish bias but bearish sweep - no liquidity score
        setup = SetupInfo(bias_h4=Bias.BULLISH, liq_sweep_bear=True)
        assert calculate_score(setup, config) == 0

    def test_mss_scores_independently(self, config):
        setup = SetupInfo(bias_h4=Bias.BULLISH, bias_h1=Bias.BEARISH, mss_bull=True)
        assert calculate_score(setup, config) == config.score_mss

    def test_bos_scores_independently(self, config):
        setup = SetupInfo(bias_h4=Bias.BULLISH, bias_h1=Bias.BEARISH, bos_bear=True)
        assert calculate_score(setup, config) == config.score_bos

    def test_fvg_scores_independently(self, config):
        setup = SetupInfo(bias_h4=Bias.BULLISH, bias_h1=Bias.BEARISH, fvg_bull=True)
        assert calculate_score(setup, config) == config.score_fvg

    def test_displacement_scores_independently(self, config):
        setup = SetupInfo(bias_h4=Bias.BULLISH, bias_h1=Bias.BEARISH, displacement_bull=True)
        assert calculate_score(setup, config) == config.score_displacement

    def test_volatility_scores_independently(self, config):
        setup = SetupInfo(bias_h4=Bias.BULLISH, bias_h1=Bias.BEARISH, volatility_active=True)
        assert calculate_score(setup, config) == config.score_volatility

    def test_session_scores_independently(self, config):
        setup = SetupInfo(bias_h4=Bias.BULLISH, bias_h1=Bias.BEARISH, session=Session.LONDON)
        assert calculate_score(setup, config) == config.score_session

    def test_trend_alignment_scores(self, config):
        # Both biases match (both NEUTRAL by default)
        setup = SetupInfo(bias_h4=Bias.NEUTRAL, bias_h1=Bias.NEUTRAL)
        assert calculate_score(setup, config) == config.score_trend

    def test_trend_misalignment_no_score(self, config):
        setup = SetupInfo(bias_h4=Bias.BULLISH, bias_h1=Bias.BEARISH)
        assert calculate_score(setup, config) == 0

    def test_custom_weights(self):
        config = EAConfig(
            score_liquidity=30,
            score_mss=10,
            score_bos=10,
            score_fvg=10,
            score_displacement=10,
            score_volatility=10,
            score_session=10,
            score_trend=10,
        )
        setup = SetupInfo(
            bias_h4=Bias.BULLISH,
            liq_sweep_bull=True,
            mss_bull=True,
        )
        assert calculate_score(setup, config) == 30 + 10

    def test_partial_score_moderate_setup(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BULLISH,
            bias_h1=Bias.BULLISH,
            session=Session.LONDON,
            liq_sweep_bull=True,
            mss_bull=True,
            bos_bull=True,
            volatility_active=True,
        )
        expected = (
            config.score_liquidity
            + config.score_mss
            + config.score_bos
            + config.score_volatility
            + config.score_session
            + config.score_trend
        )
        assert calculate_score(setup, config) == expected


class TestShouldExecuteTrade:
    """Tests for trade execution decision logic."""

    def test_buy_signal_all_conditions_met(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BULLISH,
            liq_sweep_bull=True,
            mss_bull=True,
            bos_bull=True,
            fvg_bull=True,
            volatility_active=True,
            score=85,
        )
        assert should_execute_trade(setup, config) == "BUY"

    def test_sell_signal_all_conditions_met(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BEARISH,
            liq_sweep_bear=True,
            mss_bear=True,
            bos_bear=True,
            fvg_bear=True,
            volatility_active=True,
            score=90,
        )
        assert should_execute_trade(setup, config) == "SELL"

    def test_no_signal_score_too_low(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BULLISH,
            liq_sweep_bull=True,
            mss_bull=True,
            bos_bull=True,
            fvg_bull=True,
            volatility_active=True,
            score=70,  # Below min_score_strong (80)
        )
        assert should_execute_trade(setup, config) == "NONE"

    def test_no_signal_missing_liq_sweep(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BULLISH,
            liq_sweep_bull=False,
            mss_bull=True,
            bos_bull=True,
            fvg_bull=True,
            volatility_active=True,
            score=90,
        )
        assert should_execute_trade(setup, config) == "NONE"

    def test_no_signal_missing_mss(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BULLISH,
            liq_sweep_bull=True,
            mss_bull=False,
            bos_bull=True,
            fvg_bull=True,
            volatility_active=True,
            score=90,
        )
        assert should_execute_trade(setup, config) == "NONE"

    def test_no_signal_missing_volatility(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BULLISH,
            liq_sweep_bull=True,
            mss_bull=True,
            bos_bull=True,
            fvg_bull=True,
            volatility_active=False,
            score=90,
        )
        assert should_execute_trade(setup, config) == "NONE"

    def test_no_signal_neutral_bias(self, config):
        setup = SetupInfo(
            bias_h4=Bias.NEUTRAL,
            liq_sweep_bull=True,
            mss_bull=True,
            bos_bull=True,
            fvg_bull=True,
            volatility_active=True,
            score=90,
        )
        assert should_execute_trade(setup, config) == "NONE"

    def test_score_exactly_at_threshold(self, config):
        setup = SetupInfo(
            bias_h4=Bias.BULLISH,
            liq_sweep_bull=True,
            mss_bull=True,
            bos_bull=True,
            fvg_bull=True,
            volatility_active=True,
            score=80,  # Exactly at threshold
        )
        assert should_execute_trade(setup, config) == "BUY"
