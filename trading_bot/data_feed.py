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
import math
import re
import time
from datetime import datetime, timedelta, timezone

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

# US-Handelstag: 9:30-16:00 ET = 390 Minuten reine Handelszeit. Nur zur
# Umrechnung "wie viele Kalendertage muss ich zurueckgehen" genutzt -- nicht
# fuer die Indikatorberechnung selbst.
_TRADING_MINUTES_PER_DAY = 390


def parse_timeframe(value: str) -> TimeFrame:
    match = _TIMEFRAME_RE.match(value.strip())
    if not match:
        raise ValueError(f"Invalid TIMEFRAME '{value}'. Expected e.g. '15Min', '1Hour', '1Day'.")
    amount, unit = match.groups()
    return TimeFrame(int(amount), _UNIT_MAP[unit.lower()])


def estimate_backfill_start(timeframe: TimeFrame, bars_needed: int) -> datetime:
    """Wie weit ein `start`-Datum zurueckliegen muss, damit trotz Wochenenden,
    Feiertagen und Handelspausen sicher `bars_needed` Bars der gegebenen
    Groesse zurueckkommen. Bewusst grosszuegig (Handelstage -> Kalendertage
    mit Wochenend-Faktor + fixem Feiertags-Puffer) -- ein paar Tage zu viel
    Historie anzufragen kostet nur etwas mehr Daten in der Antwort, zu wenig
    wuerde den Backfill genau um das Problem bringen, das er loesen soll.
    """
    unit = timeframe.unit
    if unit == TimeFrameUnit.Minute:
        trading_days_needed = math.ceil((bars_needed * timeframe.amount) / _TRADING_MINUTES_PER_DAY)
    elif unit == TimeFrameUnit.Hour:
        trading_days_needed = math.ceil((bars_needed * timeframe.amount * 60) / _TRADING_MINUTES_PER_DAY)
    elif unit == TimeFrameUnit.Day:
        trading_days_needed = bars_needed * timeframe.amount
    elif unit == TimeFrameUnit.Week:
        trading_days_needed = bars_needed * timeframe.amount * 5
    else:  # Month
        trading_days_needed = bars_needed * timeframe.amount * 21

    # 5 Handelstage pro 7 Kalendertage, plus 10 Tage Puffer fuer Feiertage.
    calendar_days_needed = math.ceil(trading_days_needed * 7 / 5) + 10
    return datetime.now(timezone.utc) - timedelta(days=calendar_days_needed)


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
            feed=self._config.alpaca_data_feed,
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
                feed=self._config.alpaca_data_feed,
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

    def backfill_bars(
        self,
        symbols: list[str],
        limit: int,
        retries: int = 3,
        retry_pause_seconds: float = 2.0,
    ) -> dict[str, pd.DataFrame]:
        """Laedt beim Bot-Start genug historische Bars pro Symbol, damit
        Indikatoren (SMA/EMA/RSI/MACD) direkt im ersten Zyklus vollstaendig
        berechenbar sind, statt erst tage-/wochenlang live nachzusammeln.

        Nutzt dieselbe Chunk-Strategie wie get_bars_batch (ein multi-symbol
        Request pro data_batch_size Symbole, Pause dazwischen -- haelt die
        Anzahl der HTTP-Requests bei z.B. 99 Nasdaq-100-Symbolen niedrig und
        unter Alpacas Rate-Limits), setzt aber zusaetzlich explizit ein
        `start`-Datum weit genug in der Vergangenheit (siehe
        estimate_backfill_start) und retried jeden Chunk bis zu `retries`
        mal, bevor die betroffenen Symbole als fehlgeschlagen geloggt werden
        -- ein einzelner kurzzeitiger Ausfall der Alpaca API blockiert damit
        nicht den Start der uebrigen Symbole.
        """
        start = estimate_backfill_start(self._timeframe, limit)
        results: dict[str, pd.DataFrame] = {}
        chunks = [
            symbols[i : i + self._config.data_batch_size]
            for i in range(0, len(symbols), self._config.data_batch_size)
        ]

        for i, chunk in enumerate(chunks):
            request = StockBarsRequest(
                symbol_or_symbols=chunk,
                timeframe=self._timeframe,
                start=start,
                # Gleiche Ueberlegung wie in get_bars_batch: `limit` deckelt
                # die Gesamtanzahl Bars *ueber alle Symbole* im Request.
                limit=limit * len(chunk),
                feed=self._config.alpaca_data_feed,
            )

            bar_set = None
            for attempt in range(1, retries + 1):
                try:
                    bar_set = self._data_client.get_stock_bars(request)
                    break
                except Exception as exc:
                    is_last_attempt = attempt == retries
                    level = logger.warning if not is_last_attempt else logger.error
                    level(
                        "Backfill-Request fuer %s fehlgeschlagen (Versuch %d/%d): %s",
                        chunk,
                        attempt,
                        retries,
                        exc,
                    )
                    if not is_last_attempt:
                        time.sleep(retry_pause_seconds)

            if bar_set is None:
                logger.error("Backfill fuer diese Symbole endgueltig fehlgeschlagen: %s", chunk)
            else:
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
