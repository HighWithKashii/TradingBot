"""Loads all runtime configuration from environment variables (.env)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

from trading_bot.nasdaq100 import NASDAQ_100

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
    watchlist_env: list[str] = field(default_factory=lambda: _get_list("WATCHLIST", ["AAPL"]))
    use_nasdaq100: bool = field(default_factory=lambda: _get_bool("USE_NASDAQ100", False))
    timeframe: str = field(default_factory=lambda: os.getenv("TIMEFRAME", "15Min"))
    check_interval_minutes: float = field(default_factory=lambda: _get_float("CHECK_INTERVAL_MINUTES", 15))

    # Batching for the Nasdaq-100-sized watchlist (keeps requests/minute well
    # under Alpaca's rate limits instead of firing ~100 calls back to back)
    data_batch_size: int = field(default_factory=lambda: _get_int("DATA_BATCH_SIZE", 30))
    data_batch_pause_seconds: float = field(default_factory=lambda: _get_float("DATA_BATCH_PAUSE_SECONDS", 1.0))

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
    def watchlist(self) -> list[str]:
        """The effective watchlist: the full Nasdaq-100 when USE_NASDAQ100=true,
        otherwise the fixed WATCHLIST from .env.
        """
        return list(NASDAQ_100) if self.use_nasdaq100 else self.watchlist_env

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
            raise ValueError("WATCHLIST must contain at least one symbol (or set USE_NASDAQ100=true).")
        if self.data_batch_size < 1:
            raise ValueError("DATA_BATCH_SIZE must be at least 1.")
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
