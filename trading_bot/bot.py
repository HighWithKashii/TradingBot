"""Main loop: wires data feed, strategy, risk manager, order executor and
trade logger together. Handles API failures per-symbol so one bad request
doesn't take down the whole watchlist scan, and enforces the daily loss
limit before any new entries are considered.
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
        logger.info(
            "Starting bot (%s trading) — watchlist=%s, interval=%s min",
            "paper" if self._config.paper else "LIVE",
            self._config.watchlist,
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

        for symbol in self._config.watchlist:
            try:
                self._process_symbol(symbol, equity, buying_power)
            except OrderExecutionError as exc:
                logger.error("Order/account error for %s: %s", symbol, exc)
                self._trade_logger.log(symbol=symbol, action="ERROR", reason=str(exc), status="error")
            except Exception as exc:
                logger.exception("Unexpected error while processing %s", symbol)
                self._trade_logger.log(symbol=symbol, action="ERROR", reason=repr(exc), status="error")

    def _process_symbol(self, symbol: str, equity: float, buying_power: float) -> None:
        position = self._executor.get_open_position(symbol)

        bars = self._data_feed.get_bars(symbol, limit=self._config.min_bars_required + 10)
        if bars.empty:
            self._trade_logger.log(symbol=symbol, action="HOLD", reason="No market data returned.")
            return

        df = compute_indicators(bars, self._config)
        signal = generate_signal(df, self._config, has_open_position=position is not None)
        price = float(df.iloc[-1]["close"])

        if signal.action == Action.BUY:
            self._enter_long(symbol, price, equity, buying_power, signal.reason)
        elif signal.action == Action.SELL:
            self._exit_long(symbol, position, price, signal.reason)
        else:
            self._trade_logger.log(symbol=symbol, action="HOLD", reason=signal.reason, price=price)

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
        logger.info("BUY %s x%d @ ~%.2f (SL %.2f / TP %.2f)", symbol, qty, price, prices.stop_loss, prices.take_profit)
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
        logger.info("SELL/close %s x%s @ ~%.2f (est. P&L %.2f)", symbol, qty, price, realized_pnl)
        self._trade_logger.log(
            symbol=symbol,
            action="SELL",
            reason=f"{reason} (estimated P&L {realized_pnl:.2f})",
            qty=int(qty),
            price=price,
            order_id=str(order.id),
            status=str(order.status),
        )
