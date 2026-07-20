"""Signal generation: combines an SMA/EMA trend filter with an MACD crossover
trigger and an RSI confirmation filter into a single BUY/SELL/HOLD decision.

The strategy is intentionally long-only (no short selling): it opens long
positions on bullish confluence and closes them on bearish confluence.
Whenever the indicators disagree or there isn't enough history, it returns
HOLD rather than guessing — see the "no order on unclear signals" requirement.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

import pandas as pd

from trading_bot.config import Config
from trading_bot.indicators import ema, macd, rsi, sma


class Action(str, Enum):
    BUY = "BUY"
    SELL = "SELL"
    HOLD = "HOLD"


@dataclass(frozen=True)
class SignalResult:
    action: Action
    reason: str
    indicators: dict


def _crossed_above(prev_a: float, prev_b: float, curr_a: float, curr_b: float) -> bool:
    return prev_a <= prev_b and curr_a > curr_b


def _crossed_below(prev_a: float, prev_b: float, curr_a: float, curr_b: float) -> bool:
    return prev_a >= prev_b and curr_a < curr_b


def compute_indicators(df: pd.DataFrame, config: Config) -> pd.DataFrame:
    """Adds SMA, EMA, RSI and MACD columns to a copy of the OHLCV dataframe."""
    out = df.copy()
    close = out["close"]

    out["sma_fast"] = sma(close, config.sma_fast)
    out["sma_slow"] = sma(close, config.sma_slow)
    out["ema_fast"] = ema(close, config.sma_fast)
    out["ema_slow"] = ema(close, config.sma_slow)
    out["rsi"] = rsi(close, config.rsi_period)

    macd_line, signal_line, histogram = macd(close, config.macd_fast, config.macd_slow, config.macd_signal)
    out["macd_line"] = macd_line
    out["macd_signal_line"] = signal_line
    out["macd_hist"] = histogram

    return out


def generate_signal(df: pd.DataFrame, config: Config, has_open_position: bool) -> SignalResult:
    """Evaluates the latest bar of an indicator-enriched dataframe (see
    compute_indicators) and returns the trading decision plus the reasoning
    that should be logged.
    """
    if len(df) < config.min_bars_required:
        return SignalResult(
            Action.HOLD,
            f"Not enough history yet ({len(df)}/{config.min_bars_required} bars) — skipping.",
            {},
        )

    latest = df.iloc[-1]
    prev = df.iloc[-2]

    required = ["sma_fast", "sma_slow", "rsi", "macd_line", "macd_signal_line"]
    if latest[required].isna().any() or prev[required].isna().any():
        return SignalResult(Action.HOLD, "Indicators not fully warmed up yet — skipping.", {})

    indicators = {
        "close": round(float(latest["close"]), 4),
        "sma_fast": round(float(latest["sma_fast"]), 4),
        "sma_slow": round(float(latest["sma_slow"]), 4),
        "rsi": round(float(latest["rsi"]), 2),
        "macd_line": round(float(latest["macd_line"]), 4),
        "macd_signal_line": round(float(latest["macd_signal_line"]), 4),
    }

    uptrend = latest["sma_fast"] > latest["sma_slow"]
    downtrend = latest["sma_fast"] < latest["sma_slow"]
    macd_bull_cross = _crossed_above(
        prev["macd_line"], prev["macd_signal_line"], latest["macd_line"], latest["macd_signal_line"]
    )
    macd_bear_cross = _crossed_below(
        prev["macd_line"], prev["macd_signal_line"], latest["macd_line"], latest["macd_signal_line"]
    )
    rsi_ok_for_entry = config.rsi_oversold < latest["rsi"] < config.rsi_overbought
    rsi_overbought = latest["rsi"] >= config.rsi_overbought

    if has_open_position:
        reasons = []
        if downtrend:
            reasons.append(f"death cross (SMA{config.sma_fast} < SMA{config.sma_slow})")
        if macd_bear_cross:
            reasons.append("MACD bearish crossover")
        if rsi_overbought:
            reasons.append(f"RSI overbought ({indicators['rsi']} >= {config.rsi_overbought})")
        if reasons:
            return SignalResult(Action.SELL, "Exit signal: " + ", ".join(reasons) + ".", indicators)
        return SignalResult(Action.HOLD, "Position open, no exit condition met.", indicators)

    if uptrend and macd_bull_cross and rsi_ok_for_entry:
        reason = (
            f"Uptrend (SMA{config.sma_fast} {indicators['sma_fast']} > "
            f"SMA{config.sma_slow} {indicators['sma_slow']}), MACD bullish crossover "
            f"({indicators['macd_line']} > {indicators['macd_signal_line']}), "
            f"RSI confirms momentum without being overbought ({indicators['rsi']})."
        )
        return SignalResult(Action.BUY, reason, indicators)

    missing = []
    if not uptrend:
        missing.append("no confirmed uptrend")
    if not macd_bull_cross:
        missing.append("no MACD bullish crossover this bar")
    if not rsi_ok_for_entry:
        missing.append(f"RSI outside entry range ({indicators['rsi']})")
    return SignalResult(Action.HOLD, "No entry: " + ", ".join(missing) + ".", indicators)
