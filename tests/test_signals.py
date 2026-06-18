"""Unit tests for signal detection logic (liquidity sweeps, MSS, BOS, displacement, FVG)."""

import pytest
from src.titan_logic import (
    Bias,
    detect_liquidity_sweeps,
    detect_mss,
    detect_bos,
    detect_displacement,
    detect_fvg,
    get_bias,
)


class TestDetectLiquiditySweeps:
    """Tests for DetectLiquiditySweeps() - previous day level sweeps."""

    def test_bullish_sweep_below_low(self):
        # Price swept below prev day low but closed above it
        bull, bear = detect_liquidity_sweeps(
            prev_day_high=2050.0,
            prev_day_low=2000.0,
            curr_high=2030.0,
            curr_low=1998.0,  # Below prev day low
            curr_close=2005.0,  # Closed above prev day low
        )
        assert bull is True
        assert bear is False

    def test_bearish_sweep_above_high(self):
        # Price swept above prev day high but closed below it
        bull, bear = detect_liquidity_sweeps(
            prev_day_high=2050.0,
            prev_day_low=2000.0,
            curr_high=2055.0,  # Above prev day high
            curr_low=2040.0,
            curr_close=2045.0,  # Closed below prev day high
        )
        assert bull is False
        assert bear is True

    def test_both_sweeps(self):
        # Wide range candle sweeping both levels
        bull, bear = detect_liquidity_sweeps(
            prev_day_high=2050.0,
            prev_day_low=2000.0,
            curr_high=2060.0,  # Above prev day high
            curr_low=1990.0,  # Below prev day low
            curr_close=2025.0,  # Closed between (above low, below high)
        )
        assert bull is True
        assert bear is True

    def test_no_sweep_inside_range(self):
        bull, bear = detect_liquidity_sweeps(
            prev_day_high=2050.0,
            prev_day_low=2000.0,
            curr_high=2040.0,
            curr_low=2010.0,
            curr_close=2025.0,
        )
        assert bull is False
        assert bear is False

    def test_sweep_high_but_close_above(self):
        # Swept above high and stayed above - no rejection
        bull, bear = detect_liquidity_sweeps(
            prev_day_high=2050.0,
            prev_day_low=2000.0,
            curr_high=2060.0,
            curr_low=2045.0,
            curr_close=2055.0,  # Closed above prev day high
        )
        assert bull is False
        assert bear is False

    def test_sweep_low_but_close_below(self):
        # Swept below low and stayed below - no rejection
        bull, bear = detect_liquidity_sweeps(
            prev_day_high=2050.0,
            prev_day_low=2000.0,
            curr_high=2010.0,
            curr_low=1990.0,
            curr_close=1995.0,  # Closed below prev day low
        )
        assert bull is False
        assert bear is False


class TestDetectMSS:
    """Tests for DetectMSS() - Market Structure Shift."""

    def test_bullish_mss(self):
        highs = [2010.0, 2020.0, 2015.0, 2025.0, 2030.0]
        lows = [2000.0, 2005.0, 2003.0, 2010.0, 2015.0]
        # close_h1 > highs[2] (2015) with bullish bias
        mss_bull, mss_bear = detect_mss(Bias.BULLISH, 2018.0, highs, lows)
        assert mss_bull is True
        assert mss_bear is False

    def test_bearish_mss(self):
        highs = [2010.0, 2020.0, 2015.0, 2025.0, 2030.0]
        lows = [2000.0, 2005.0, 2003.0, 2010.0, 2015.0]
        # close_h1 < lows[2] (2003) with bearish bias
        mss_bull, mss_bear = detect_mss(Bias.BEARISH, 2001.0, highs, lows)
        assert mss_bull is False
        assert mss_bear is True

    def test_no_mss_wrong_bias(self):
        highs = [2010.0, 2020.0, 2015.0, 2025.0, 2030.0]
        lows = [2000.0, 2005.0, 2003.0, 2010.0, 2015.0]
        # Bearish bias but close > highs[2]
        mss_bull, mss_bear = detect_mss(Bias.BEARISH, 2018.0, highs, lows)
        assert mss_bull is False
        assert mss_bear is False

    def test_no_mss_close_within_range(self):
        highs = [2010.0, 2020.0, 2015.0, 2025.0, 2030.0]
        lows = [2000.0, 2005.0, 2003.0, 2010.0, 2015.0]
        mss_bull, mss_bear = detect_mss(Bias.BULLISH, 2012.0, highs, lows)
        assert mss_bull is False
        assert mss_bear is False

    def test_insufficient_data(self):
        mss_bull, mss_bear = detect_mss(Bias.BULLISH, 2020.0, [2010.0, 2020.0], [2000.0, 2005.0])
        assert mss_bull is False
        assert mss_bear is False


class TestDetectBOS:
    """Tests for DetectBOS() - Break of Structure."""

    def test_bullish_bos(self):
        # Close above swing high of previous 10 bars
        highs = [0] + [2020.0, 2025.0, 2030.0, 2028.0, 2022.0, 2015.0, 2018.0, 2024.0, 2026.0, 2019.0]
        lows = [0] + [2010.0, 2015.0, 2020.0, 2018.0, 2012.0, 2005.0, 2008.0, 2014.0, 2016.0, 2009.0]
        # swing_high = max(highs[1:10]) = 2030
        bos_bull, bos_bear = detect_bos(Bias.BULLISH, 2035.0, highs, lows)
        assert bos_bull is True
        assert bos_bear is False

    def test_bearish_bos(self):
        highs = [0] + [2020.0, 2025.0, 2030.0, 2028.0, 2022.0, 2015.0, 2018.0, 2024.0, 2026.0, 2019.0]
        lows = [0] + [2010.0, 2015.0, 2020.0, 2018.0, 2012.0, 2005.0, 2008.0, 2014.0, 2016.0, 2009.0]
        # swing_low = min(lows[1:10]) = 2005
        bos_bull, bos_bear = detect_bos(Bias.BEARISH, 2003.0, highs, lows)
        assert bos_bull is False
        assert bos_bear is True

    def test_no_bos_within_range(self):
        highs = [0] + [2020.0, 2025.0, 2030.0, 2028.0, 2022.0, 2015.0, 2018.0, 2024.0, 2026.0, 2019.0]
        lows = [0] + [2010.0, 2015.0, 2020.0, 2018.0, 2012.0, 2005.0, 2008.0, 2014.0, 2016.0, 2009.0]
        bos_bull, bos_bear = detect_bos(Bias.BULLISH, 2025.0, highs, lows)
        assert bos_bull is False
        assert bos_bear is False

    def test_no_bos_wrong_bias(self):
        highs = [0] + [2020.0, 2025.0, 2030.0, 2028.0, 2022.0, 2015.0, 2018.0, 2024.0, 2026.0, 2019.0]
        lows = [0] + [2010.0, 2015.0, 2020.0, 2018.0, 2012.0, 2005.0, 2008.0, 2014.0, 2016.0, 2009.0]
        # Close > swing high but bias is bearish
        bos_bull, bos_bear = detect_bos(Bias.BEARISH, 2035.0, highs, lows)
        assert bos_bull is False
        assert bos_bear is False

    def test_insufficient_data(self):
        bos_bull, bos_bear = detect_bos(Bias.BULLISH, 2035.0, [2020.0] * 5, [2010.0] * 5)
        assert bos_bull is False
        assert bos_bear is False


class TestDetectDisplacement:
    """Tests for DetectDisplacement() - strong momentum candle detection."""

    def test_bullish_displacement(self):
        # Large bullish body relative to ATR, small wicks
        bull, bear = detect_displacement(
            open_price=1950.0,
            close_price=1970.0,  # Body = 20
            high_price=1972.0,  # Upper wick = 2 (< 20*0.3=6)
            low_price=1949.0,  # Lower wick = 1 (< 6)
            atr=10.0,  # body/atr = 2.0 > 1.5
        )
        assert bull is True
        assert bear is False

    def test_bearish_displacement(self):
        bull, bear = detect_displacement(
            open_price=1970.0,
            close_price=1950.0,  # Body = 20
            high_price=1971.0,  # Upper wick = 1
            low_price=1948.0,  # Lower wick = 2
            atr=10.0,
        )
        assert bull is False
        assert bear is True

    def test_no_displacement_body_too_small(self):
        # Body = 5, ATR = 10, ratio = 0.5 < 1.5
        bull, bear = detect_displacement(
            open_price=1950.0,
            close_price=1955.0,
            high_price=1957.0,
            low_price=1949.0,
            atr=10.0,
        )
        assert bull is False
        assert bear is False

    def test_no_displacement_large_upper_wick(self):
        # Body = 20, upper wick = 8 > body*0.3=6
        bull, bear = detect_displacement(
            open_price=1950.0,
            close_price=1970.0,
            high_price=1978.0,  # Upper wick = 8
            low_price=1949.0,
            atr=10.0,
        )
        assert bull is False
        assert bear is False

    def test_no_displacement_large_lower_wick(self):
        # Body = 20, lower wick = 8 > body*0.3=6
        bull, bear = detect_displacement(
            open_price=1950.0,
            close_price=1970.0,
            high_price=1971.0,
            low_price=1942.0,  # Lower wick = 8
            atr=10.0,
        )
        assert bull is False
        assert bear is False

    def test_zero_atr_returns_false(self):
        bull, bear = detect_displacement(
            open_price=1950.0,
            close_price=1970.0,
            high_price=1971.0,
            low_price=1949.0,
            atr=0.0,
        )
        assert bull is False
        assert bear is False

    def test_negative_atr_returns_false(self):
        bull, bear = detect_displacement(
            open_price=1950.0,
            close_price=1970.0,
            high_price=1971.0,
            low_price=1949.0,
            atr=-5.0,
        )
        assert bull is False
        assert bear is False

    def test_custom_displacement_factor(self):
        # Body = 12, ATR = 10, factor 1.0 -> 12/10=1.2 > 1.0
        bull, bear = detect_displacement(
            open_price=1950.0,
            close_price=1962.0,
            high_price=1963.0,
            low_price=1949.0,
            atr=10.0,
            displacement_factor=1.0,
        )
        assert bull is True


class TestDetectFVG:
    """Tests for DetectFVG() - Fair Value Gap detection."""

    def test_bullish_fvg(self):
        # Gap up: low1 > high2, bullish close2, price in zone
        # For bullish FVG: price <= high2 AND price >= low1 - 10*point
        # With point=1.0: gap can be up to $10
        fvg_bull, fvg_bear = detect_fvg(
            high1=2020.0,
            low1=2015.0,   # low of candle 2
            high2=2010.0,  # high of candle 3
            low2=2005.0,
            close2=2008.0,  # Bullish close (> open)
            open2=2006.0,
            current_bid=2008.0,  # <= high2(2010) and >= low1-10*1.0(2005)
            current_ask=2008.5,
            point=1.0,  # Gold with 1-point precision
        )
        assert fvg_bull is True
        assert fvg_bear is False

    def test_bearish_fvg(self):
        # Gap down: high1 < low2, bearish close2, price in zone
        # For bearish FVG: price >= low2 AND price <= high1 + 10*point
        # With point=1.0: tolerance of $10
        fvg_bull, fvg_bear = detect_fvg(
            high1=2005.0,  # high of candle 2
            low1=2000.0,
            high2=2015.0,
            low2=2010.0,   # low of candle 3
            close2=2012.0,  # Bearish close (< open)
            open2=2014.0,
            current_bid=2009.0,
            current_ask=2012.0,  # >= low2(2010) AND <= high1+10*1.0(2015)
            point=1.0,  # Gold with 1-point precision
        )
        assert fvg_bull is False
        assert fvg_bear is True

    def test_no_fvg_no_gap(self):
        # No gap: low1 <= high2
        fvg_bull, fvg_bear = detect_fvg(
            high1=2020.0,
            low1=2010.0,
            high2=2012.0,  # Overlaps with low1
            low2=2005.0,
            close2=2008.0,
            open2=2006.0,
            current_bid=2009.0,
            current_ask=2009.5,
        )
        assert fvg_bull is False
        assert fvg_bear is False

    def test_bullish_fvg_price_outside_gap(self):
        # Gap exists but price not in the gap
        fvg_bull, fvg_bear = detect_fvg(
            high1=2020.0,
            low1=2015.0,
            high2=2010.0,
            low2=2005.0,
            close2=2008.0,
            open2=2006.0,
            current_bid=2020.0,  # Price above the gap
            current_ask=2020.5,
            point=0.01,
        )
        assert fvg_bull is False

    def test_bearish_fvg_wrong_close_direction(self):
        # Gap down but close2 > open2 (bullish candle 3 - doesn't qualify)
        fvg_bull, fvg_bear = detect_fvg(
            high1=2005.0,
            low1=2000.0,
            high2=2015.0,
            low2=2010.0,
            close2=2014.0,  # Bullish close > open
            open2=2012.0,
            current_bid=2009.0,
            current_ask=2010.5,
        )
        assert fvg_bear is False


class TestGetBias:
    """Tests for GetBias() - market bias determination."""

    def test_bullish_bias(self):
        # Higher high, higher low, price above EMA
        highs = [2000.0, 2020.0, 2010.0]  # highs[1] > highs[2]
        lows = [1990.0, 2005.0, 2000.0]   # lows[1] > lows[2]
        bias = get_bias(highs, lows, price_close=2015.0, ema_value=2000.0)
        assert bias == Bias.BULLISH

    def test_bearish_bias(self):
        # Lower high, lower low, price below EMA
        highs = [2020.0, 2005.0, 2010.0]  # highs[1] < highs[2]
        lows = [2000.0, 1995.0, 2000.0]   # lows[1] < lows[2]
        bias = get_bias(highs, lows, price_close=1998.0, ema_value=2005.0)
        assert bias == Bias.BEARISH

    def test_neutral_bias_no_structure(self):
        # Higher high but lower low (indecision)
        highs = [2000.0, 2020.0, 2010.0]  # HH
        lows = [1990.0, 1995.0, 2000.0]   # LL
        bias = get_bias(highs, lows, price_close=2015.0, ema_value=2000.0)
        assert bias == Bias.NEUTRAL

    def test_neutral_bias_price_below_ema_for_bullish(self):
        # HH + HL but price below EMA
        highs = [2000.0, 2020.0, 2010.0]
        lows = [1990.0, 2005.0, 2000.0]
        bias = get_bias(highs, lows, price_close=1998.0, ema_value=2010.0)
        assert bias == Bias.NEUTRAL

    def test_insufficient_data(self):
        bias = get_bias([2000.0, 2010.0], [1990.0, 1995.0], 2005.0, 2000.0)
        assert bias == Bias.NEUTRAL
