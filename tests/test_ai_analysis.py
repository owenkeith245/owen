"""Unit tests for AI analysis scoring logic."""

import pytest
from src.scalper_logic import (
    AnalysisWeights,
    ModuleScores,
    calculate_weighted_score,
    score_trend,
    score_spread,
    score_volatility,
    score_volume,
    determine_signal,
    calculate_quality_stars,
)


class TestCalculateWeightedScore:
    def test_perfect_scores(self):
        scores = ModuleScores(trend=100, liquidity=100, momentum=100,
                              volume=100, structure=100, volatility=100, spread=100)
        weights = AnalysisWeights()
        result = calculate_weighted_score(scores, weights)
        assert result == pytest.approx(100.0)

    def test_zero_scores(self):
        scores = ModuleScores()
        weights = AnalysisWeights()
        result = calculate_weighted_score(scores, weights)
        assert result == 0.0

    def test_balanced_mid_scores(self):
        scores = ModuleScores(trend=50, liquidity=50, momentum=50,
                              volume=50, structure=50, volatility=50, spread=50)
        weights = AnalysisWeights()
        result = calculate_weighted_score(scores, weights)
        assert result == pytest.approx(50.0)

    def test_weights_sum_to_one(self):
        w = AnalysisWeights()
        total = w.trend + w.liquidity + w.momentum + w.volume + w.structure + w.volatility + w.spread
        assert total == pytest.approx(1.0)

    def test_trend_dominant(self):
        scores = ModuleScores(trend=100, liquidity=0, momentum=0,
                              volume=0, structure=0, volatility=0, spread=0)
        weights = AnalysisWeights()
        result = calculate_weighted_score(scores, weights)
        assert result == pytest.approx(20.0)  # 100 * 0.20

    def test_clamps_to_100(self):
        scores = ModuleScores(trend=150, liquidity=150, momentum=150,
                              volume=150, structure=150, volatility=150, spread=150)
        weights = AnalysisWeights()
        result = calculate_weighted_score(scores, weights)
        assert result == 100.0


class TestScoreTrend:
    def test_strong_uptrend(self):
        score = score_trend(ema_fast=2000.0, ema_slow=1990.0, ema_slope=0.02, adx=35)
        assert score > 70

    def test_strong_downtrend(self):
        score = score_trend(ema_fast=1990.0, ema_slow=2000.0, ema_slope=-0.02, adx=35)
        assert score < 30

    def test_neutral_no_adx(self):
        score = score_trend(ema_fast=2000.0, ema_slow=2000.0, ema_slope=0.0, adx=15)
        assert 30 <= score <= 70

    def test_clamped_to_bounds(self):
        score = score_trend(ema_fast=2100.0, ema_slow=1900.0, ema_slope=0.1, adx=80)
        assert 0 <= score <= 100


class TestScoreSpread:
    def test_tight_spread(self):
        score = score_spread(10.0, 12.0)
        assert score == 100.0  # ratio < 1.2 gets +10 but capped at 100

    def test_normal_spread(self):
        score = score_spread(15.0, 12.0)
        # ratio = 1.25, >= 1.2 so no +10 bonus, but < 1.5 so no deduction
        assert score == pytest.approx(100.0)

    def test_wide_spread(self):
        score = score_spread(30.0, 12.0)
        # ratio = 2.5, >= 2.0 so -50, also > 1.5 so -(2.5-1)*20 = -30
        assert score == pytest.approx(max(0, 100 - 50 - (2.5 - 1.0) * 20))

    def test_zero_avg(self):
        assert score_spread(15.0, 0.0) == 100.0


class TestScoreVolatility:
    def test_healthy_volatility(self):
        # ratio = 1.0 (in 0.8-1.5 range), tick_vol = 1.0 (in 0-2 range)
        score = score_volatility(current_atr=5.0, avg_atr=5.0, tick_vol=1.0)
        assert score == pytest.approx(90.0)  # 50 + 25 + 15

    def test_too_volatile(self):
        # ratio = 3.0 > 2.0
        score = score_volatility(current_atr=15.0, avg_atr=5.0, tick_vol=6.0)
        assert score == pytest.approx(10.0)  # 50 - 25 - 15

    def test_too_quiet(self):
        # ratio = 0.2 < 0.5
        score = score_volatility(current_atr=1.0, avg_atr=5.0, tick_vol=0.5)
        assert score == pytest.approx(50.0)  # 50 - 15 + 15

    def test_zero_avg_atr(self):
        score = score_volatility(current_atr=5.0, avg_atr=0.0, tick_vol=1.0)
        assert score == pytest.approx(65.0)  # 50 + 15


class TestScoreVolume:
    def test_high_activity(self):
        score = score_volume(tick_speed=10.0, total_depth=5000.0)
        # +15 from speed, +5 from depth
        assert score > 65

    def test_dead_market(self):
        score = score_volume(tick_speed=0.5, total_depth=0.0)
        assert score == pytest.approx(30.0)  # 50 - 20

    def test_moderate_activity(self):
        score = score_volume(tick_speed=5.0, total_depth=1000.0)
        assert score == pytest.approx(51.0)  # 50 + 0 + 1


class TestDetermineSignal:
    def test_buy_signal(self):
        direction, conf = determine_signal(90.0, 60.0, 85.0)
        assert direction == "BUY"
        assert conf == 90.0

    def test_sell_signal(self):
        direction, conf = determine_signal(50.0, 88.0, 85.0)
        assert direction == "SELL"
        assert conf == 88.0

    def test_no_signal_below_threshold(self):
        direction, conf = determine_signal(70.0, 60.0, 85.0)
        assert direction == "NONE"
        assert conf == 70.0

    def test_no_signal_equal_scores(self):
        direction, conf = determine_signal(85.0, 85.0, 85.0)
        assert direction == "NONE"

    def test_threshold_exact(self):
        direction, conf = determine_signal(85.0, 80.0, 85.0)
        assert direction == "BUY"


class TestQualityStars:
    def test_five_stars(self):
        assert calculate_quality_stars(100.0) == 5

    def test_four_stars(self):
        assert calculate_quality_stars(85.0) == 4

    def test_three_stars(self):
        assert calculate_quality_stars(65.0) == 3

    def test_zero_stars(self):
        assert calculate_quality_stars(10.0) == 0
