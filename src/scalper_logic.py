"""
GoldAIScalper - Core Logic Module (Python port for testing)

Ports the pure algorithmic logic from the MQL5 AI scalping bot,
including tick processing, AI scoring, risk management, position
management, signal detection, and news filtering.
"""

import math
from dataclasses import dataclass, field
from enum import IntEnum
from typing import List, Tuple, Optional


# === Tick Engine Logic ===

@dataclass
class TickData:
    bid: float = 0.0
    ask: float = 0.0
    spread: float = 0.0
    volume: float = 0.0
    time_ms: int = 0


@dataclass
class TickMetrics:
    buy_pressure: float = 0.0
    sell_pressure: float = 0.0
    net_flow: float = 0.0
    tick_speed: float = 0.0
    price_velocity: float = 0.0
    acceleration: float = 0.0
    current_spread: float = 0.0
    avg_spread: float = 0.0
    spread_ratio: float = 0.0
    spread_normal: bool = True
    liquidity_imbalance: float = 0.0
    tick_volatility: float = 0.0
    high_since_reset: float = 0.0
    low_since_reset: float = float('inf')
    vwap: float = 0.0


def calculate_order_flow(upticks: int, downticks: int) -> Tuple[float, float, float]:
    """Calculate buy/sell pressure from tick counts."""
    total = upticks + downticks
    if total == 0:
        return (0.0, 0.0, 0.0)
    buy_pressure = upticks / total
    sell_pressure = downticks / total
    net_flow = buy_pressure - sell_pressure
    return (buy_pressure, sell_pressure, net_flow)


def calculate_tick_volatility(price_changes: List[float]) -> float:
    """Calculate standard deviation of tick-to-tick price changes."""
    if len(price_changes) < 10:
        return 0.0
    count = min(len(price_changes), 100)
    changes = price_changes[:count]
    mean = sum(changes) / count
    variance = sum((c - mean) ** 2 for c in changes) / count
    return math.sqrt(abs(variance))


def is_spread_normal(current_spread: float, avg_spread: float, max_ratio: float = 2.0) -> bool:
    """Check if current spread is within acceptable range."""
    if avg_spread <= 0:
        return True
    return (current_spread / avg_spread) < max_ratio


# === AI Analysis Logic ===

@dataclass
class AnalysisWeights:
    trend: float = 0.20
    liquidity: float = 0.20
    momentum: float = 0.15
    volume: float = 0.15
    structure: float = 0.15
    volatility: float = 0.10
    spread: float = 0.05


@dataclass
class ModuleScores:
    trend: float = 0.0
    liquidity: float = 0.0
    momentum: float = 0.0
    volume: float = 0.0
    structure: float = 0.0
    volatility: float = 0.0
    spread: float = 0.0


def calculate_weighted_score(scores: ModuleScores, weights: AnalysisWeights) -> float:
    """Calculate overall weighted confidence score."""
    result = (
        scores.trend * weights.trend
        + scores.liquidity * weights.liquidity
        + scores.momentum * weights.momentum
        + scores.volume * weights.volume
        + scores.structure * weights.structure
        + scores.volatility * weights.volatility
        + scores.spread * weights.spread
    )
    return max(0.0, min(100.0, result))


def score_trend(ema_fast: float, ema_slow: float, ema_slope: float, adx: float) -> float:
    """Score trend strength 0-100."""
    score = 50.0
    if ema_fast > ema_slow:
        score += 20.0
    else:
        score -= 20.0
    score += min(ema_slope * 1000, 15.0) if ema_slope > 0 else max(ema_slope * 1000, -15.0)
    if adx > 25:
        score += min((adx - 25) * 0.5, 15.0)
    return max(0.0, min(100.0, score))


def score_spread(current_spread: float, avg_spread: float) -> float:
    """Score spread quality 0-100."""
    score = 100.0
    if avg_spread <= 0:
        return score
    ratio = current_spread / avg_spread
    if ratio >= 2.0:
        score -= 50.0
    if ratio > 1.5:
        score -= (ratio - 1.0) * 20.0
    elif ratio < 1.2:
        score += 10.0
    return max(0.0, min(100.0, score))


def score_volatility(current_atr: float, avg_atr: float, tick_vol: float) -> float:
    """Score volatility quality 0-100."""
    score = 50.0
    if avg_atr > 0:
        ratio = current_atr / avg_atr
        if 0.8 <= ratio <= 1.5:
            score += 25.0
        elif ratio > 2.0:
            score -= 25.0
        elif ratio < 0.5:
            score -= 15.0
    if 0 < tick_vol < 2.0:
        score += 15.0
    elif tick_vol > 5.0:
        score -= 15.0
    return max(0.0, min(100.0, score))


def score_volume(tick_speed: float, total_depth: float) -> float:
    """Score volume/activity 0-100."""
    score = 50.0
    if tick_speed > 5.0:
        score += min((tick_speed - 5.0) * 3.0, 25.0)
    elif tick_speed < 1.0:
        score -= 20.0
    if total_depth > 0:
        score += min(total_depth * 0.001, 25.0)
    return max(0.0, min(100.0, score))


def determine_signal(buy_score: float, sell_score: float, min_confidence: float) -> Tuple[str, float]:
    """Determine trade direction based on scores."""
    if buy_score > sell_score and buy_score >= min_confidence:
        return ("BUY", buy_score)
    elif sell_score > buy_score and sell_score >= min_confidence:
        return ("SELL", sell_score)
    return ("NONE", max(buy_score, sell_score))


def calculate_quality_stars(confidence: float) -> int:
    """Convert confidence to 0-5 star rating."""
    return int(confidence / 20.0)


# === Risk Management Logic ===

@dataclass
class RiskConfig:
    max_daily_risk_percent: float = 2.0
    max_weekly_risk_percent: float = 5.0
    max_single_trade_risk: float = 0.5
    max_open_trades: int = 10
    max_spread_multiplier: float = 2.5
    emergency_drawdown: float = 5.0
    max_consecutive_losses: int = 5


@dataclass
class RiskState:
    daily_risk_used: float = 0.0
    daily_risk_budget: float = 0.0
    open_trade_count: int = 0
    consecutive_losses: int = 0
    halt_daily: bool = False
    halt_weekly: bool = False
    halt_emergency: bool = False
    halt_consecutive: bool = False


def can_trade(state: RiskState, config: RiskConfig) -> bool:
    """Check if trading is allowed given current risk state."""
    if state.halt_daily or state.halt_weekly or state.halt_emergency or state.halt_consecutive:
        return False
    if state.open_trade_count >= config.max_open_trades:
        return False
    if state.daily_risk_budget > 0 and state.daily_risk_used >= state.daily_risk_budget:
        return False
    return True


def allocate_risk(
    balance: float,
    config: RiskConfig,
    state: RiskState,
    stop_loss_points: float,
    point_value: float,
    confidence: float,
    lot_step: float = 0.01,
    lot_min: float = 0.01,
    lot_max: float = 100.0,
) -> Tuple[bool, float, float, str]:
    """
    Allocate risk for a new trade.
    Returns: (approved, lot_size, risk_money, reject_reason)
    """
    if not can_trade(state, config):
        return (False, 0.0, 0.0, "HALTED")

    available_risk = state.daily_risk_budget - state.daily_risk_used
    max_trade_risk = balance * config.max_single_trade_risk / 100.0

    confidence_scale = min(confidence / 100.0, 1.0)
    risk_money = min(max_trade_risk * confidence_scale, available_risk)

    if risk_money <= 0:
        return (False, 0.0, 0.0, "NO RISK BUDGET")

    if stop_loss_points <= 0 or point_value <= 0:
        return (False, 0.0, 0.0, "INVALID SL")

    lot_size = risk_money / (stop_loss_points * point_value)
    lot_size = math.floor(lot_size / lot_step) * lot_step
    if lot_size < lot_min:
        return (False, 0.0, 0.0, "LOT TOO SMALL")
    if lot_size > lot_max:
        lot_size = lot_max

    return (True, lot_size, risk_money, "")


def check_weekly_drawdown(week_start_balance: float, current_balance: float, max_dd_percent: float) -> bool:
    """Returns True if weekly drawdown limit exceeded."""
    if week_start_balance <= 0:
        return False
    dd = (week_start_balance - current_balance) / week_start_balance * 100
    return dd > max_dd_percent


def check_emergency_drawdown(day_start_balance: float, current_balance: float, emergency_percent: float) -> bool:
    """Returns True if emergency drawdown hit."""
    if day_start_balance <= 0:
        return False
    dd = (day_start_balance - current_balance) / day_start_balance * 100
    return dd > emergency_percent


# === Position Management Logic ===

class TradeState(IntEnum):
    OPEN = 0
    BREAKEVEN = 1
    TRAILING = 2
    PARTIAL_CLOSED = 3


def calculate_profit_r(entry: float, current_price: float, stop_loss: float, is_buy: bool) -> float:
    """Calculate profit in R-multiples."""
    risk = abs(entry - stop_loss)
    if risk <= 0:
        return 0.0
    if is_buy:
        profit = current_price - entry
    else:
        profit = entry - current_price
    return profit / risk


def should_move_to_breakeven(profit_r: float, break_even_r: float, sl: float, entry: float, is_buy: bool) -> bool:
    """Check if SL should move to breakeven."""
    if profit_r < break_even_r:
        return False
    if is_buy:
        return sl < entry
    return sl > entry


def calculate_trailing_stop(current_price: float, current_sl: float, atr: float, trail_mult: float, is_buy: bool) -> float:
    """Calculate new trailing SL. Returns new SL or current_sl if no change."""
    trail_dist = atr * trail_mult
    if is_buy:
        new_sl = current_price - trail_dist
        return new_sl if new_sl > current_sl else current_sl
    else:
        new_sl = current_price + trail_dist
        return new_sl if new_sl < current_sl else current_sl


def calculate_partial_close_volume(initial_lots: float, close_percent: float, lot_step: float, lot_min: float) -> float:
    """Calculate volume for partial close."""
    volume = math.floor((initial_lots * close_percent) / lot_step) * lot_step
    if volume < lot_min:
        return 0.0
    return volume


def calculate_take_profit(entry: float, stop_loss: float, rr_ratio: float, is_buy: bool) -> float:
    """Calculate take profit level."""
    risk = abs(entry - stop_loss)
    if is_buy:
        return entry + risk * rr_ratio
    return entry - risk * rr_ratio


# === Signal Detection Logic ===

def detect_swing_high(highs: List[float], index: int) -> bool:
    """Check if index is a swing high (higher than 2 neighbors each side)."""
    if index < 2 or index >= len(highs) - 2:
        return False
    return (highs[index] > highs[index-1] and highs[index] > highs[index-2] and
            highs[index] > highs[index+1] and highs[index] > highs[index+2])


def detect_swing_low(lows: List[float], index: int) -> bool:
    """Check if index is a swing low (lower than 2 neighbors each side)."""
    if index < 2 or index >= len(lows) - 2:
        return False
    return (lows[index] < lows[index-1] and lows[index] < lows[index-2] and
            lows[index] < lows[index+1] and lows[index] < lows[index+2])


def detect_bullish_fvg(high_older: float, low_newer: float) -> bool:
    """Detect if a bullish FVG (gap up) exists between two candles."""
    return low_newer > high_older


def detect_bearish_fvg(low_older: float, high_newer: float) -> bool:
    """Detect if a bearish FVG (gap down) exists between two candles."""
    return high_newer < low_older


def detect_order_block(
    candle_close: float, candle_open: float,
    next_close: float, next_open: float, next_high: float, next_low: float,
    candle_high: float,  candle_low: float,
) -> Tuple[bool, bool]:
    """
    Detect bullish/bearish order blocks.
    Returns: (is_bullish_ob, is_bearish_ob)
    """
    next_body = abs(next_close - next_open)
    next_range = next_high - next_low
    if next_range <= 0:
        return (False, False)

    body_ratio = next_body / next_range

    # Bullish OB: bearish candle followed by strong bullish displacement above it
    is_bullish_ob = (candle_close < candle_open and  # bearish candle
                     next_close > next_open and       # bullish follow
                     body_ratio > 0.6 and             # strong body
                     next_close > candle_high)        # displacement above

    # Bearish OB: bullish candle followed by strong bearish displacement below it
    is_bearish_ob = (candle_close > candle_open and  # bullish candle
                     next_close < next_open and       # bearish follow
                     body_ratio > 0.6 and             # strong body
                     next_close < candle_low)         # displacement below

    return (is_bullish_ob, is_bearish_ob)


def calculate_structure_score(
    liq_sweep: bool, fvg_present: bool, ob_present: bool, mss: bool, bos: bool
) -> float:
    """Calculate combined market structure score."""
    score = 0.0
    if liq_sweep:
        score += 25
    if fvg_present:
        score += 20
    if ob_present:
        score += 20
    if mss:
        score += 20
    if bos:
        score += 15
    return min(score, 100.0)


# === News Filter Logic ===

def is_nfp_window(day_of_week: int, day: int, hour: int, minute: int, quiet_minutes: int = 15) -> bool:
    """Check if within NFP news window (1st Friday, 15:30 EAT)."""
    if day_of_week != 5 or day > 7:
        return False
    event_min = 15 * 60 + 30
    current_min = hour * 60 + minute
    return event_min - quiet_minutes <= current_min <= event_min + quiet_minutes


def is_fomc_window(day_of_week: int, day: int, hour: int, minute: int, quiet_minutes: int = 15) -> bool:
    """Check if within FOMC window (3rd Wednesday, 21:00 EAT)."""
    if day_of_week != 3 or day < 15 or day > 21:
        return False
    event_min = 21 * 60
    current_min = hour * 60 + minute
    return event_min - quiet_minutes <= current_min <= event_min + quiet_minutes


def is_active_session(hour: int, london_start: int = 9, london_end: int = 12,
                      ny_start: int = 15, ny_end: int = 18, trade_asian: bool = False) -> bool:
    """Check if current hour is within an active trading session."""
    if london_start <= hour < london_end:
        return True
    if ny_start <= hour < ny_end:
        return True
    if trade_asian and 2 <= hour < 9:
        return True
    return False


# === Trade Logger Logic ===

@dataclass
class TradeRecord:
    profit: float = 0.0
    profit_percent: float = 0.0
    r_multiple: float = 0.0
    confidence: float = 0.0
    session: str = ""
    is_win: bool = False


def calculate_win_rate(wins: int, total: int) -> float:
    """Calculate win rate percentage."""
    if total == 0:
        return 0.0
    return wins / total * 100.0


def calculate_profit_factor(total_wins: float, total_losses: float) -> float:
    """Calculate profit factor (gross wins / gross losses)."""
    if total_losses <= 0:
        return 999.0
    return total_wins / total_losses


def calculate_sharpe_ratio(returns: List[float]) -> float:
    """Calculate annualized Sharpe ratio."""
    if len(returns) < 2:
        return 0.0
    mean = sum(returns) / len(returns)
    variance = sum((r - mean) ** 2 for r in returns) / len(returns)
    stddev = math.sqrt(abs(variance))
    if stddev == 0:
        return 0.0
    return mean / stddev * math.sqrt(252)


def get_adaptive_threshold(
    high_conf_win_rate: float, med_conf_win_rate: float, trade_count: int
) -> float:
    """Get adaptive confidence threshold based on historical performance."""
    if trade_count < 20:
        return 85.0
    if high_conf_win_rate > 70:
        return 85.0
    if med_conf_win_rate > 65:
        return 80.0
    return 90.0
