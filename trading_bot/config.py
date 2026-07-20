"""Loads all runtime configuration from environment variables (.env)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

load_dotenv()


def _get_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


def _get_float(name: str, default: float) -> float:
    value = os.getenv(name)
    return float(value) if value else default


def _get_int(name: str, default: int) -> int:
    value = os.getenv(name)
    return int(value) if value else default


def _get_list(name: str, default: list[str]) -> list[str]:
    value = os.getenv(name)
    if not value:
        return default
    return [symbol.strip().upper() for symbol in value.split(",") if symbol.strip()]


@dataclass(frozen=True)
class Config:
    # Alpaca credentials / endpoint
    api_key: str = field(default_factory=lambda: os.getenv("ALPACA_API_KEY", ""))
    secret_key: str = field(default_factory=lambda: os.getenv("ALPACA_SECRET_KEY", ""))
    paper: bool = field(default_factory=lambda: _get_bool("ALPACA_PAPER", True))

    # Watchlist / timing
    watchlist: list[str] = field(default_factory=lambda: _get_list("WATCHLIST", ["AAPL"]))
    timeframe: str = field(default_factory=lambda: os.getenv("TIMEFRAME", "15Min"))
    check_interval_minutes: float = field(default_factory=lambda: _get_float("CHECK_INTERVAL_MINUTES", 15))

    # Strategy parameters
    sma_fast: int = field(default_factory=lambda: _get_int("SMA_FAST", 50))
    sma_slow: int = field(default_factory=lambda: _get_int("SMA_SLOW", 200))
    rsi_period: int = field(default_factory=lambda: _get_int("RSI_PERIOD", 14))
    rsi_overbought: float = field(default_factory=lambda: _get_float("RSI_OVERBOUGHT", 70))
    rsi_oversold: float = field(default_factory=lambda: _get_float("RSI_OVERSOLD", 30))
    macd_fast: int = field(default_factory=lambda: _get_int("MACD_FAST", 12))
    macd_slow: int = field(default_factory=lambda: _get_int("MACD_SLOW", 26))
    macd_signal: int = field(default_factory=lambda: _get_int("MACD_SIGNAL", 9))

    # Risk management
    position_size_pct: float = field(default_factory=lambda: _get_float("POSITION_SIZE_PCT", 2.0))
    stop_loss_pct: float = field(default_factory=lambda: _get_float("STOP_LOSS_PCT", 2.0))
    take_profit_pct: float = field(default_factory=lambda: _get_float("TAKE_PROFIT_PCT", 4.0))
    max_daily_loss_pct: float = field(default_factory=lambda: _get_float("MAX_DAILY_LOSS_PCT", 3.0))

    # Logging
    trade_log_path: str = field(default_factory=lambda: os.getenv("TRADE_LOG_PATH", "trades.csv"))

    @property
    def min_bars_required(self) -> int:
        """Minimum bar history needed before indicators are considered valid."""
        return max(self.sma_slow, self.macd_slow + self.macd_signal, self.rsi_period) + 5

    def validate(self) -> None:
        if not self.api_key or not self.secret_key:
            raise ValueError(
                "ALPACA_API_KEY / ALPACA_SECRET_KEY are missing. Copy .env.example to .env and fill them in."
            )
        if not self.watchlist:
            raise ValueError("WATCHLIST must contain at least one symbol.")
        if self.sma_fast >= self.sma_slow:
            raise ValueError("SMA_FAST must be smaller than SMA_SLOW.")
        if not (0 < self.position_size_pct <= 100):
            raise ValueError("POSITION_SIZE_PCT must be between 0 and 100.")
        if not (0 < self.max_daily_loss_pct <= 100):
            raise ValueError("MAX_DAILY_LOSS_PCT must be between 0 and 100.")


def load_config() -> Config:
    config = Config()
    config.validate()
    return config
