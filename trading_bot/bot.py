"""Main loop: wires data feed, strategy, risk manager, order executor and
trade logger together. Handles API failures per-symbol so one bad request
doesn't take down the whole watchlist scan, and enforces the daily loss
limit before any new entries are considered.

Positions and bars for the whole watchlist are fetched once per cycle in
bulk (one get_all_positions() call, a handful of chunked get_bars_batch()
calls) instead of per symbol, so scanning ~100 Nasdaq-100 names doesn't
turn into ~200 individual API requests. Per-symbol HOLD decisions are only
written to trades.csv; the console gets one summary line per cycle instead
of one line per symbol.
"""

from __future__ import annotations

import logging
import time
from datetime import datetime, timezone

from trading_bot.config import Config
from trading_bot.data_feed import MarketDataFeed
from trading_bot.order_executor import OrderExecutionError, OrderExecutor
from trading_bot.risk_manager import RiskManager
from trading_bot.strategy import Action, compute_indicators, generate_signal
from trading_bot.trade_logger import TradeLogger

try:
    from colorama import Fore, Style
    from colorama import init as _colorama_init

    _colorama_init()
except ImportError:  # colorama not installed -> plain, uncolored output
    class _NoColor:
        def __getattr__(self, _name: str) -> str:
            return ""

    Fore = _NoColor()
    Style = _NoColor()

logger = logging.getLogger("trading_bot")


class TradingBot:
    def __init__(
        self,
        config: Config,
        data_feed: MarketDataFeed,
        executor: OrderExecutor,
        risk_manager: RiskManager,
        trade_logger: TradeLogger,
    ):
        self._config = config
        self._data_feed = data_feed
        self._executor = executor
        self._risk_manager = risk_manager
        self._trade_logger = trade_logger

    def run_forever(self) -> None:
        source = "Nasdaq-100" if self._config.use_nasdaq100 else "fixed list"
        logger.info(
            "Starting bot (%s trading) — watchlist: %d symbols (%s), interval=%s min",
            "paper" if self._config.paper else "LIVE",
            len(self._config.watchlist),
            source,
            self._config.check_interval_minutes,
        )
        while True:
            try:
                self.run_cycle()
            except OrderExecutionError as exc:
                logger.error("Alpaca API error during cycle: %s", exc)
            except Exception:
                logger.exception("Unexpected error during trading cycle")
            time.sleep(self._config.check_interval_minutes * 60)

    def run_cycle(self) -> None:
        cycle_start = time.monotonic()
        try:
            if not self._data_feed.is_market_open():
                logger.info("Market is closed — skipping cycle.")
                return
        except OrderExecutionError as exc:
            logger.error("Could not check market clock: %s", exc)
            return

        account = self._executor.get_account()
        equity = float(account.equity)
        buying_power = float(account.buying_power)
        today = datetime.now(timezone.utc).date()
        self._risk_manager.start_new_day_if_needed(today, equity)

        if self._risk_manager.daily_loss_limit_hit():
            logger.warning(
                "Daily loss limit reached (realized P&L today: %.2f) — no new trades until tomorrow.",
                self._risk_manager.realized_pnl_today,
            )
            self._trade_logger.log(
                symbol="ALL",
                action="HALT",
                reason=f"Daily loss limit hit (P&L today {self._risk_manager.realized_pnl_today:.2f}).",
            )
            return

        watchlist = self._config.watchlist

        try:
            positions = self._executor.get_all_positions()
        except OrderExecutionError as exc:
            logger.error("Could not fetch open positions — skipping cycle: %s", exc)
            return

        bars_by_symbol = self._data_feed.get_bars_batch(watchlist, limit=self._config.min_bars_required + 10)

        counts = {"BUY": 0, "SELL": 0, "HOLD": 0, "ERROR": 0}
        for symbol in watchlist:
            action = self._process_symbol(
                symbol, bars_by_symbol.get(symbol), positions.get(symbol), equity, buying_power
            )
            counts[action] = counts.get(action, 0) + 1

        elapsed = time.monotonic() - cycle_start
        summary = f"{counts['BUY']} BUY, {counts['SELL']} SELL, {counts['HOLD']} HOLD"
        if counts["ERROR"]:
            summary += f", {counts['ERROR']} ERROR"
        logger.info("Scan complete: %s (duration: %.1fs)", summary, elapsed)

    def _process_symbol(self, symbol, bars, position, equity: float, buying_power: float) -> str:
        try:
            if bars is None or bars.empty:
                self._trade_logger.log(symbol=symbol, action="HOLD", reason="No market data returned.")
                return "HOLD"

            df = compute_indicators(bars, self._config)
            signal = generate_signal(df, self._config, has_open_position=position is not None)
            price = float(df.iloc[-1]["close"])

            if signal.action == Action.BUY:
                self._enter_long(symbol, price, equity, buying_power, signal.reason)
                return "BUY"
            elif signal.action == Action.SELL:
                self._exit_long(symbol, position, price, signal.reason)
                return "SELL"
            else:
                self._trade_logger.log(symbol=symbol, action="HOLD", reason=signal.reason, price=price)
                return "HOLD"
        except OrderExecutionError as exc:
            logger.error("Order/account error for %s: %s", symbol, exc)
            self._trade_logger.log(symbol=symbol, action="ERROR", reason=str(exc), status="error")
            return "ERROR"
        except Exception as exc:
            logger.exception("Unexpected error while processing %s", symbol)
            self._trade_logger.log(symbol=symbol, action="ERROR", reason=repr(exc), status="error")
            return "ERROR"

    def _enter_long(self, symbol: str, price: float, equity: float, buying_power: float, reason: str) -> None:
        qty = self._risk_manager.calculate_position_size(equity, buying_power, price)
        if qty < 1:
            self._trade_logger.log(
                symbol=symbol,
                action="HOLD",
                reason=f"Entry signal present but position size rounds to 0 shares at ${price:.2f} "
                f"(buying power ${buying_power:.2f}). {reason}",
                price=price,
            )
            return

        prices = self._risk_manager.calculate_bracket_prices(price)
        order = self._executor.submit_bracket_buy(symbol, qty, prices)
        logger.info(
            f"{Fore.GREEN}BUY {symbol} x{qty} @ ~{price:.2f} "
            f"(SL {prices.stop_loss:.2f} / TP {prices.take_profit:.2f}) — {reason}{Style.RESET_ALL}"
        )
        self._trade_logger.log(
            symbol=symbol,
            action="BUY",
            reason=reason,
            qty=qty,
            price=price,
            stop_loss=prices.stop_loss,
            take_profit=prices.take_profit,
            order_id=str(order.id),
            status=str(order.status),
        )

    def _exit_long(self, symbol: str, position, price: float, reason: str) -> None:
        if position is None:
            self._trade_logger.log(
                symbol=symbol, action="HOLD", reason="Exit signal but no open position found.", price=price
            )
            return

        realized_pnl = float(position.unrealized_pl)
        qty = float(position.qty)
        order = self._executor.close_position(symbol)
        self._risk_manager.register_realized_pnl(realized_pnl)
        logger.info(
            f"{Fore.RED}SELL {symbol} x{qty:g} @ ~{price:.2f} "
            f"(est. P&L {realized_pnl:.2f}) — {reason}{Style.RESET_ALL}"
        )
        self._trade_logger.log(
            symbol=symbol,
            action="SELL",
            reason=f"{reason} (estimated P&L {realized_pnl:.2f})",
            qty=int(qty),
            price=price,
            order_id=str(order.id),
            status=str(order.status),
        )
