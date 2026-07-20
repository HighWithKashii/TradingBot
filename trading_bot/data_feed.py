"""Wraps Alpaca's market data API: historical bars for indicator calculation
and the trading clock used to check whether the market is open.

Bars for multi-symbol watchlists (e.g. the full Nasdaq-100) are fetched in
chunks via get_bars_batch() rather than one HTTP request per symbol, to stay
well under Alpaca's data API rate limits. Note that Alpaca's `limit`
parameter on the multi-symbol bars endpoint caps the *total* number of bars
across all symbols in the request (not per symbol), so the requested limit
is scaled up by the batch size and trimmed back down per symbol afterwards.
"""

from __future__ import annotations

import logging
import re
import time

import pandas as pd
from alpaca.data.historical import StockHistoricalDataClient
from alpaca.data.requests import StockBarsRequest
from alpaca.data.timeframe import TimeFrame, TimeFrameUnit
from alpaca.trading.client import TradingClient
from alpaca.trading.models import Clock

from trading_bot.config import Config

logger = logging.getLogger("trading_bot")

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

    def get_bars_batch(self, symbols: list[str], limit: int) -> dict[str, pd.DataFrame]:
        """Fetches recent bars for many symbols using as few HTTP requests as
        possible: symbols are split into chunks of config.data_batch_size,
        one multi-symbol request per chunk, with a short pause between
        chunks. Returns {symbol: DataFrame}; symbols with no data are
        omitted (caller/strategy treats missing history as HOLD).
        """
        results: dict[str, pd.DataFrame] = {}
        chunks = [
            symbols[i : i + self._config.data_batch_size]
            for i in range(0, len(symbols), self._config.data_batch_size)
        ]

        for i, chunk in enumerate(chunks):
            request = StockBarsRequest(
                symbol_or_symbols=chunk,
                timeframe=self._timeframe,
                # Alpaca's `limit` caps the total bar count across *all*
                # symbols in the request, not per symbol -- scale it up so
                # every symbol in the chunk still gets its full history.
                limit=limit * len(chunk),
            )
            try:
                bar_set = self._data_client.get_stock_bars(request)
            except Exception:
                logger.exception("Failed to fetch bar batch for %s", chunk)
                continue

            df = bar_set.df
            if not df.empty and isinstance(df.index, pd.MultiIndex):
                for symbol in df.index.get_level_values("symbol").unique():
                    symbol_df = df.xs(symbol, level="symbol")[["open", "high", "low", "close", "volume"]]
                    results[symbol] = symbol_df.sort_index().tail(limit)
            elif not df.empty and len(chunk) == 1:
                results[chunk[0]] = df[["open", "high", "low", "close", "volume"]].sort_index().tail(limit)

            if i < len(chunks) - 1 and self._config.data_batch_pause_seconds > 0:
                time.sleep(self._config.data_batch_pause_seconds)

        return results

    def get_latest_price(self, symbol: str) -> float:
        bars = self.get_bars(symbol, limit=1)
        if bars.empty:
            raise RuntimeError(f"No market data returned for {symbol}.")
        return float(bars.iloc[-1]["close"])

    def get_clock(self) -> Clock:
        return self._trading_client.get_clock()

    def is_market_open(self) -> bool:
        return bool(self.get_clock().is_open)
