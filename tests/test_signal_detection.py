"""Unit tests for signal detection logic."""

import pytest
from src.scalper_logic import (
    detect_swing_high,
    detect_swing_low,
    detect_bullish_fvg,
    detect_bearish_fvg,
    detect_order_block,
    calculate_structure_score,
)


class TestDetectSwingHigh:
    def test_valid_swing_high(self):
        highs = [2000, 2005, 2010, 2015, 2020, 2015, 2010, 2005, 2000]
        assert detect_swing_high(highs, 4) is True

    def test_not_swing_high(self):
        highs = [2000, 2005, 2010, 2015, 2020, 2025, 2030]
        assert detect_swing_high(highs, 3) is False

    def test_boundary_index_low(self):
        highs = [2020, 2015, 2010, 2005, 2000]
        assert detect_swing_high(highs, 0) is False

    def test_boundary_index_high(self):
        highs = [2000, 2005, 2010, 2015, 2020]
        assert detect_swing_high(highs, 4) is False

    def test_equal_neighbors(self):
        highs = [2010, 2010, 2015, 2010, 2010]
        assert detect_swing_high(highs, 2) is True


class TestDetectSwingLow:
    def test_valid_swing_low(self):
        lows = [2020, 2015, 2010, 2005, 2000, 2005, 2010, 2015, 2020]
        assert detect_swing_low(lows, 4) is True

    def test_not_swing_low(self):
        lows = [2030, 2025, 2020, 2015, 2010, 2005, 2000]
        assert detect_swing_low(lows, 3) is False

    def test_boundary_index(self):
        lows = [2000, 2005, 2010]
        assert detect_swing_low(lows, 1) is False


class TestDetectBullishFVG:
    def test_gap_exists(self):
        assert detect_bullish_fvg(high_older=2010.0, low_newer=2015.0) is True

    def test_no_gap(self):
        assert detect_bullish_fvg(high_older=2015.0, low_newer=2010.0) is False

    def test_touching(self):
        assert detect_bullish_fvg(high_older=2010.0, low_newer=2010.0) is False


class TestDetectBearishFVG:
    def test_gap_exists(self):
        assert detect_bearish_fvg(low_older=2015.0, high_newer=2010.0) is True

    def test_no_gap(self):
        assert detect_bearish_fvg(low_older=2010.0, high_newer=2015.0) is False

    def test_touching(self):
        assert detect_bearish_fvg(low_older=2010.0, high_newer=2010.0) is False


class TestDetectOrderBlock:
    def test_bullish_ob(self):
        # Bearish candle (close < open) followed by strong bullish displacement above
        bull, bear = detect_order_block(
            candle_close=2000.0, candle_open=2005.0,  # bearish
            next_close=2015.0, next_open=2006.0,       # bullish
            next_high=2016.0, next_low=2005.0,         # strong body (9/11 > 0.6)
            candle_high=2006.0, candle_low=1999.0,
        )
        assert bull is True
        assert bear is False

    def test_bearish_ob(self):
        # Bullish candle (close > open) followed by strong bearish displacement below
        bull, bear = detect_order_block(
            candle_close=2005.0, candle_open=2000.0,  # bullish
            next_close=1990.0, next_open=1999.0,       # bearish
            next_high=2000.0, next_low=1989.0,         # strong body (9/11 > 0.6)
            candle_high=2006.0, candle_low=1999.0,
        )
        assert bull is False
        assert bear is True

    def test_no_ob_weak_follow(self):
        bull, bear = detect_order_block(
            candle_close=2000.0, candle_open=2005.0,
            next_close=2003.0, next_open=2002.0,  # weak move
            next_high=2010.0, next_low=2000.0,     # body/range = 1/10 < 0.6
            candle_high=2006.0, candle_low=1999.0,
        )
        assert bull is False
        assert bear is False

    def test_no_ob_zero_range(self):
        bull, bear = detect_order_block(
            candle_close=2000.0, candle_open=2005.0,
            next_close=2010.0, next_open=2005.0,
            next_high=2010.0, next_low=2010.0,  # zero range
            candle_high=2006.0, candle_low=1999.0,
        )
        assert bull is False
        assert bear is False


class TestCalculateStructureScore:
    def test_all_signals(self):
        score = calculate_structure_score(
            liq_sweep=True, fvg_present=True, ob_present=True, mss=True, bos=True
        )
        assert score == 100.0

    def test_no_signals(self):
        score = calculate_structure_score(
            liq_sweep=False, fvg_present=False, ob_present=False, mss=False, bos=False
        )
        assert score == 0.0

    def test_partial_signals(self):
        score = calculate_structure_score(
            liq_sweep=True, fvg_present=True, ob_present=False, mss=False, bos=False
        )
        assert score == 45.0

    def test_capped_at_100(self):
        score = calculate_structure_score(
            liq_sweep=True, fvg_present=True, ob_present=True, mss=True, bos=True
        )
        assert score <= 100.0

    def test_mss_and_bos(self):
        score = calculate_structure_score(
            liq_sweep=False, fvg_present=False, ob_present=False, mss=True, bos=True
        )
        assert score == 35.0
