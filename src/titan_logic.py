"""
TitanGoldHunterPro - Core Logic Module (Python port)

This module contains the pure algorithmic logic extracted from the MQL5 EA,
making it testable outside of MetaTrader 5. Each function mirrors the
corresponding MQL5 function's behavior using plain data inputs.
"""

from enum import IntEnum
from dataclasses import dataclass, field
from datetime import datetime
import math


# --- Enums ---

class Bias(IntEnum):
    BULLISH = 0
    BEARISH = 1
    NEUTRAL = 2


class Session(IntEnum):
    NONE = 0
    LONDON = 1
    NEWYORK = 2


# --- Configuration ---

@dataclass
class EAConfig:
    """Input parameters matching the MQL5 EA's input group settings."""

    # Risk Management
    risk_percent: float = 1.0
    max_daily_risk: float = 3.0
    max_daily_losses: int = 3
    max_weekly_dd: float = 5.0
    rr_ratio1: float = 2.0
    trail_start_r: float = 1.0
    trail_step_r: float = 2.0

    # Session Times (EAT/UTC+3)
    london_start: int = 9
    london_end: int = 12
    newyork_start: int = 15
    newyork_end: int = 18

    # Technical Parameters
    ma_period: int = 50
    atr_period: int = 20
    displacement_factor: float = 1.5
    atr_mult_sl: float = 0.5
    volatility_min_factor: float = 0.8
    spread_max_mult: float = 2.0

    # News Filter
    use_news_filter: bool = True
    news_quiet_minutes: int = 15

    # Scoring Weights
    score_liquidity: int = 20
    score_mss: int = 15
    score_bos: int = 20
    score_fvg: int = 15
    score_displacement: int = 15
    score_volatility: int = 5
    score_session: int = 5
    score_trend: int = 5

    # Minimum Scores
    min_score_elite: int = 90
    min_score_strong: int = 80
    min_score_moderate: int = 70


# --- Setup Info ---

@dataclass
class SetupInfo:
    """Mirrors the MQL5 SetupInfo struct."""

    bias_h4: Bias = Bias.NEUTRAL
    bias_h1: Bias = Bias.NEUTRAL
    session: Session = Session.NONE
    liq_sweep_bull: bool = False
    liq_sweep_bear: bool = False
    mss_bull: bool = False
    mss_bear: bool = False
    bos_bull: bool = False
    bos_bear: bool = False
    fvg_bull: bool = False
    fvg_bear: bool = False
    displacement_bull: bool = False
    displacement_bear: bool = False
    volatility_active: bool = False
    score: float = 0.0


# --- Pure Logic Functions ---

def get_current_session(hour: int, config: EAConfig) -> Session:
    """Determine trading session based on current hour."""
    if config.london_start <= hour < config.london_end:
        return Session.LONDON
    if config.newyork_start <= hour < config.newyork_end:
        return Session.NEWYORK
    return Session.NONE


def get_bias(highs: list, lows: list, price_close: float, ema_value: float) -> Bias:
    """
    Determine market bias from price structure and EMA.

    Args:
        highs: List of high prices (index 0 = oldest in the recent window)
        lows: List of low prices
        price_close: Most recent close price
        ema_value: Current EMA value
    """
    if len(highs) < 3 or len(lows) < 3:
        return Bias.NEUTRAL

    higher_high = highs[1] > highs[2]
    higher_low = lows[1] > lows[2]
    lower_high = highs[1] < highs[2]
    lower_low = lows[1] < lows[2]

    if higher_high and higher_low and price_close > ema_value:
        return Bias.BULLISH
    if lower_high and lower_low and price_close < ema_value:
        return Bias.BEARISH
    return Bias.NEUTRAL


def calculate_score(setup: SetupInfo, config: EAConfig) -> int:
    """Calculate confluence score based on setup signals and weights."""
    score = 0

    if ((setup.bias_h4 == Bias.BULLISH and setup.liq_sweep_bull) or
            (setup.bias_h4 == Bias.BEARISH and setup.liq_sweep_bear)):
        score += config.score_liquidity

    if setup.mss_bull or setup.mss_bear:
        score += config.score_mss

    if setup.bos_bull or setup.bos_bear:
        score += config.score_bos

    if setup.fvg_bull or setup.fvg_bear:
        score += config.score_fvg

    if setup.displacement_bull or setup.displacement_bear:
        score += config.score_displacement

    if setup.volatility_active:
        score += config.score_volatility

    if setup.session != Session.NONE:
        score += config.score_session

    if setup.bias_h4 == setup.bias_h1:
        score += config.score_trend

    return score


def detect_displacement(
    open_price: float,
    close_price: float,
    high_price: float,
    low_price: float,
    atr: float,
    displacement_factor: float = 1.5,
) -> tuple:
    """
    Detect displacement candle (strong momentum candle with small wicks).

    Returns:
        (displacement_bull, displacement_bear) tuple of bools
    """
    if atr <= 0:
        return (False, False)

    body = abs(close_price - open_price)
    upper_wick = high_price - max(open_price, close_price)
    lower_wick = min(open_price, close_price) - low_price

    if body > displacement_factor * atr and upper_wick < body * 0.3 and lower_wick < body * 0.3:
        if close_price > open_price:
            return (True, False)
        else:
            return (False, True)
    return (False, False)


def detect_liquidity_sweeps(
    prev_day_high: float,
    prev_day_low: float,
    curr_high: float,
    curr_low: float,
    curr_close: float,
) -> tuple:
    """
    Detect liquidity sweeps above/below previous day levels.

    Returns:
        (liq_sweep_bull, liq_sweep_bear) tuple of bools
    """
    liq_sweep_bull = False
    liq_sweep_bear = False

    # Bearish sweep: price swept above prev day high but closed below it
    if curr_high > prev_day_high and curr_close < prev_day_high:
        liq_sweep_bear = True

    # Bullish sweep: price swept below prev day low but closed above it
    if curr_low < prev_day_low and curr_close > prev_day_low:
        liq_sweep_bull = True

    return (liq_sweep_bull, liq_sweep_bear)


def detect_mss(
    bias_h1: Bias,
    close_h1: float,
    highs: list,
    lows: list,
) -> tuple:
    """
    Detect Market Structure Shift (MSS).

    Args:
        bias_h1: Current H1 bias
        close_h1: H1 close price
        highs: H1 high prices (at least 3 elements)
        lows: H1 low prices (at least 3 elements)

    Returns:
        (mss_bull, mss_bear) tuple of bools
    """
    if len(highs) < 3 or len(lows) < 3:
        return (False, False)

    mss_bull = False
    mss_bear = False

    if bias_h1 == Bias.BULLISH and close_h1 > highs[2]:
        mss_bull = True

    if bias_h1 == Bias.BEARISH and close_h1 < lows[2]:
        mss_bear = True

    return (mss_bull, mss_bear)


def detect_bos(
    bias_h1: Bias,
    close_price: float,
    highs: list,
    lows: list,
) -> tuple:
    """
    Detect Break of Structure (BOS).

    Args:
        bias_h1: Current H1 bias
        close_price: Most recent H1 close
        highs: H1 high prices (at least 10 elements)
        lows: H1 low prices (at least 10 elements)

    Returns:
        (bos_bull, bos_bear) tuple of bools
    """
    if len(highs) < 10 or len(lows) < 10:
        return (False, False)

    swing_high = highs[1]
    swing_low = lows[1]
    for i in range(2, 10):
        if highs[i] > swing_high:
            swing_high = highs[i]
        if lows[i] < swing_low:
            swing_low = lows[i]

    bos_bull = bias_h1 == Bias.BULLISH and close_price > swing_high
    bos_bear = bias_h1 == Bias.BEARISH and close_price < swing_low

    return (bos_bull, bos_bear)


def detect_fvg(
    high1: float,
    low1: float,
    high2: float,
    low2: float,
    close2: float,
    open2: float,
    current_bid: float,
    current_ask: float,
    point: float = 0.01,
) -> tuple:
    """
    Detect Fair Value Gap (FVG).

    Args:
        high1: High of candle at index 2 (most recent of the pair)
        low1: Low of candle at index 2
        high2: High of candle at index 3 (older)
        low2: Low of candle at index 3
        close2: Close of candle at index 3
        open2: Open of candle at index 3
        current_bid: Current bid price
        current_ask: Current ask price
        point: Minimum point value (default for gold = 0.01)

    Returns:
        (fvg_bull, fvg_bear) tuple of bools
    """
    fvg_bull = False
    fvg_bear = False

    # Bullish FVG: gap up, price retracing into the gap
    if low1 > high2 and close2 > open2:
        if current_bid <= high2 and current_bid >= low1 - 10 * point:
            fvg_bull = True

    # Bearish FVG: gap down, price retracing into the gap
    if high1 < low2 and close2 < open2:
        if current_ask >= low2 and current_ask <= high1 + 10 * point:
            fvg_bear = True

    return (fvg_bull, fvg_bear)


def normalize_lot(lot: float, step: float, min_lot: float, max_lot: float) -> float:
    """Normalize lot size to broker constraints."""
    lot = math.floor(lot / step) * step
    if lot < min_lot:
        return min_lot
    if lot > max_lot:
        return max_lot
    return lot


def calculate_lot_size(
    balance: float,
    risk_percent: float,
    entry: float,
    stop_loss: float,
    point_value: float,
) -> float:
    """Calculate position size based on risk parameters."""
    risk_money = balance * (risk_percent / 100.0)
    distance = abs(entry - stop_loss)
    if distance <= 0 or point_value <= 0:
        return 0.0
    return risk_money / (distance * point_value)


def calculate_tp(entry: float, stop_loss: float, rr_ratio: float, is_buy: bool) -> float:
    """Calculate take-profit price based on risk-reward ratio."""
    risk = abs(entry - stop_loss)
    if is_buy:
        return entry + risk * rr_ratio
    else:
        return entry - risk * rr_ratio


def is_news_event(day_of_week: int, day: int, hour: int, minute: int, quiet_minutes: int = 15) -> bool:
    """
    Check if current time is within a news event window.
    NFP: first Friday of month at 15:30 EAT.
    """
    if day_of_week == 5 and day <= 7 and hour == 15:
        if (30 - quiet_minutes) <= minute <= (30 + quiet_minutes):
            return True
    return False


def get_monday_midnight(day_of_week: int, timestamp: int, hour: int, minute: int, sec: int) -> int:
    """
    Calculate timestamp of Monday midnight for the current week.

    Args:
        day_of_week: 0=Sunday, 1=Monday, ..., 6=Saturday
        timestamp: Current Unix timestamp
        hour: Current hour
        minute: Current minute
        sec: Current second
    """
    if day_of_week == 0:
        days_since_monday = 6
    else:
        days_since_monday = day_of_week - 1
    monday = timestamp - days_since_monday * 86400 - hour * 3600 - minute * 60 - sec
    return monday


def check_weekly_drawdown(week_start_balance: float, current_balance: float, max_weekly_dd: float) -> bool:
    """Check if weekly drawdown limit is exceeded. Returns True if halted."""
    if week_start_balance <= 0:
        return False
    dd = (week_start_balance - current_balance) / week_start_balance * 100
    return dd > max_weekly_dd


def should_move_sl_to_be(profit_r: float, trail_start_r: float, sl: float, entry: float, is_buy: bool) -> bool:
    """Check if stop loss should be moved to breakeven."""
    if profit_r < trail_start_r:
        return False
    if is_buy:
        return sl < entry
    else:
        return sl > entry


def calculate_trailing_sl(
    current_price: float,
    current_sl: float,
    atr: float,
    is_buy: bool,
) -> float:
    """
    Calculate new trailing stop loss.
    Returns new SL if it should be updated, otherwise returns current_sl.
    """
    trail_dist = 0.5 * atr
    if is_buy:
        new_sl = current_price - trail_dist
        if new_sl > current_sl:
            return new_sl
    else:
        new_sl = current_price + trail_dist
        if new_sl < current_sl:
            return new_sl
    return current_sl


def bias_to_string(bias: Bias) -> str:
    """Convert Bias enum to display string."""
    if bias == Bias.BULLISH:
        return "BULLISH"
    if bias == Bias.BEARISH:
        return "BEARISH"
    return "NEUTRAL"


def session_to_string(session: Session) -> str:
    """Convert Session enum to display string."""
    if session == Session.LONDON:
        return "LONDON"
    if session == Session.NEWYORK:
        return "NEW YORK"
    return "CLOSED"


def should_execute_trade(setup: SetupInfo, config: EAConfig) -> str:
    """
    Determine if a trade should be executed based on setup signals.

    Returns:
        "BUY", "SELL", or "NONE"
    """
    if (setup.bias_h4 == Bias.BULLISH and setup.liq_sweep_bull and setup.mss_bull
            and setup.bos_bull and setup.fvg_bull and setup.volatility_active
            and setup.score >= config.min_score_strong):
        return "BUY"

    if (setup.bias_h4 == Bias.BEARISH and setup.liq_sweep_bear and setup.mss_bear
            and setup.bos_bear and setup.fvg_bear and setup.volatility_active
            and setup.score >= config.min_score_strong):
        return "SELL"

    return "NONE"
