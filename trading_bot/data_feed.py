"""Wraps Alpaca's market data API: historical bars for indicator calculation
and the trading clock used to check whether the market is open.
"""

from __future__ import annotations

import re

import pandas as pd
from alpaca.data.historical import StockHistoricalDataClient
from alpaca.data.requests import StockBarsRequest
from alpaca.data.timeframe import TimeFrame, TimeFrameUnit
from alpaca.trading.client import TradingClient
from alpaca.trading.models import Clock

from trading_bot.config import Config

_TIMEFRAME_RE = re.compile(r"^(\d+)(Min|Hour|Day|Week|Month)$", re.IGNORECASE)
_UNIT_MAP = {
    "min": TimeFrameUnit.Minute,
    "hour": TimeFrameUnit.Hour,
    "day": TimeFrameUnit.Day,
    "week": TimeFrameUnit.Week,
    "month": TimeFrameUnit.Month,
}


def parse_timeframe(value: str) -> TimeFrame:
    match = _TIMEFRAME_RE.match(value.strip())
    if not match:
        raise ValueError(f"Invalid TIMEFRAME '{value}'. Expected e.g. '15Min', '1Hour', '1Day'.")
    amount, unit = match.groups()
    return TimeFrame(int(amount), _UNIT_MAP[unit.lower()])


class MarketDataFeed:
    def __init__(self, config: Config, trading_client: TradingClient | None = None):
        self._config = config
        self._data_client = StockHistoricalDataClient(config.api_key, config.secret_key)
        self._trading_client = trading_client or TradingClient(
            config.api_key, config.secret_key, paper=config.paper
        )
        self._timeframe = parse_timeframe(config.timeframe)

    def get_bars(self, symbol: str, limit: int) -> pd.DataFrame:
        """Returns a DataFrame of recent OHLCV bars for one symbol, oldest first."""
        request = StockBarsRequest(
            symbol_or_symbols=symbol,
            timeframe=self._timeframe,
            limit=limit,
        )
        bar_set = self._data_client.get_stock_bars(request)
        df = bar_set.df
        if df.empty:
            return pd.DataFrame(columns=["open", "high", "low", "close", "volume"])

        if isinstance(df.index, pd.MultiIndex):
            df = df.xs(symbol, level="symbol")
        return df[["open", "high", "low", "close", "volume"]].sort_index()

    def get_latest_price(self, symbol: str) -> float:
        bars = self.get_bars(symbol, limit=1)
        if bars.empty:
            raise RuntimeError(f"No market data returned for {symbol}.")
        return float(bars.iloc[-1]["close"])

    def get_clock(self) -> Clock:
        return self._trading_client.get_clock()

    def is_market_open(self) -> bool:
        return bool(self.get_clock().is_open)
