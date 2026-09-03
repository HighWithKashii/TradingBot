"""Everything that talks to Alpaca's trading (order/account) endpoint.

Entries are placed as bracket orders so the stop-loss and take-profit legs
are attached atomically at order submission time. Exits go through
close_position(), which first cancels any still-open orders for the symbol
(in particular the bracket's stop-loss/take-profit legs) -- closing a
position while its bracket legs are still open fails on Alpaca with
"insufficient qty available for order", because those legs hold the shares
reserved. Cancellation is confirmed via a short poll/retry loop since it
completes asynchronously on Alpaca's side.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass

from alpaca.common.exceptions import APIError
from alpaca.trading.client import TradingClient
from alpaca.trading.enums import OrderClass, OrderSide, OrderType, QueryOrderStatus, TimeInForce
from alpaca.trading.models import Order, Position, TradeAccount
from alpaca.trading.requests import (
    GetOrdersRequest,
    MarketOrderRequest,
    StopLossRequest,
    StopOrderRequest,
    TakeProfitRequest,
)

from trading_bot.config import Config
from trading_bot.risk_manager import BracketPrices

logger = logging.getLogger("trading_bot")


class OrderExecutionError(Exception):
    pass


class OrderExecutor:
    _STOP_ORDER_TYPES = (OrderType.STOP, OrderType.STOP_LIMIT, OrderType.TRAILING_STOP)

    def __init__(
        self,
        config: Config,
        cancel_poll_attempts: int = 5,
        cancel_poll_interval_seconds: float = 1.0,
        close_retry_attempts: int = 3,
        close_retry_backoff_seconds: float = 2.0,
    ):
        self._client = TradingClient(config.api_key, config.secret_key, paper=config.paper)
        # How long to wait for order-cancellation (esp. bracket SL/TP legs) to
        # actually clear before giving up and attempting close_position anyway.
        self._cancel_poll_attempts = cancel_poll_attempts
        self._cancel_poll_interval_seconds = cancel_poll_interval_seconds
        # close_position can still race the cancellation on Alpaca's side --
        # retry a couple of times with backoff before surfacing the error.
        self._close_retry_attempts = close_retry_attempts
        self._close_retry_backoff_seconds = close_retry_backoff_seconds

    def get_account(self) -> TradeAccount:
        try:
            return self._client.get_account()
        except APIError as exc:
            raise OrderExecutionError(f"Failed to fetch account info: {exc}") from exc

    def get_open_position(self, symbol: str) -> Position | None:
        try:
            return self._client.get_open_position(symbol)
        except APIError as exc:
            if getattr(exc, "status_code", None) == 404 or "position does not exist" in str(exc).lower():
                return None
            raise OrderExecutionError(f"Failed to fetch position for {symbol}: {exc}") from exc

    def get_all_positions(self) -> dict[str, Position]:
        """Fetches every open position in a single call -- used instead of
        get_open_position() per symbol when scanning a large watchlist, so a
        100-symbol scan costs one request instead of up to 100.
        """
        try:
            positions = self._client.get_all_positions()
        except APIError as exc:
            raise OrderExecutionError(f"Failed to fetch open positions: {exc}") from exc
        return {position.symbol: position for position in positions}

    def submit_bracket_buy(self, symbol: str, qty: int, prices: BracketPrices) -> Order:
        # GTC, nicht DAY: mit DAY liefe die Take-Profit-Limit-Order zum
        # Handelsschluss ab, sobald sie nicht gefuellt wurde -- und weil
        # TP/SL als One-Cancels-Other verknuepft sind, storniert Alpaca beim
        # Ablauf automatisch AUCH den Stop-Loss. Die Position liefe danach
        # bis zum naechsten regulaeren Exit-Signal komplett ungeschuetzt
        # weiter (siehe Bugreport: PYPL/MRVL mit 10-15% statt ~2% Verlust).
        # GTC ist fuer Bracket-Orders auf Alpaca-Aktien (regulaere
        # Handelszeit, kein extended_hours) unterstuetzt; ausserhalb der
        # regulaeren Handelszeit (extended_hours=True) erlaubt Alpaca fuer
        # den Entry nur noch DAY + Limit-Order -- dieser Bot setzt
        # extended_hours nirgends, betrifft ihn also nicht. Fuer Crypto
        # bietet Alpaca ueberhaupt keine Bracket-/OCO-Orders an (nur simple
        # Orders) -- ebenfalls irrelevant, dieser Bot handelt ausschliesslich
        # US-Aktien.
        order_request = MarketOrderRequest(
            symbol=symbol,
            qty=qty,
            side=OrderSide.BUY,
            time_in_force=TimeInForce.GTC,
            order_class=OrderClass.BRACKET,
            take_profit=TakeProfitRequest(limit_price=prices.take_profit),
            stop_loss=StopLossRequest(stop_price=prices.stop_loss),
        )
        try:
            return self._client.submit_order(order_request)
        except APIError as exc:
            raise OrderExecutionError(f"Failed to submit bracket buy order for {symbol}: {exc}") from exc

    def _get_open_orders(self, symbol: str) -> list[Order]:
        request = GetOrdersRequest(status=QueryOrderStatus.OPEN, symbols=[symbol])
        try:
            return self._client.get_orders(request)
        except APIError as exc:
            raise OrderExecutionError(f"Failed to fetch open orders for {symbol}: {exc}") from exc

    def has_active_stop_loss(self, symbol: str) -> bool:
        """True, wenn fuer `symbol` gerade eine offene SELL-Stop-Order
        existiert (typischerweise das Stop-Loss-Leg einer Bracket-Order).
        Sicherheitsnetz-Check aus bot.py: eine offene Position sollte NIE
        ohne aktiven Stop dastehen, egal aus welchem Grund (siehe
        submit_bracket_buy's GTC-Kommentar zum urspruenglichen Bug).
        """
        return any(
            order.side == OrderSide.SELL and order.type in self._STOP_ORDER_TYPES
            for order in self._get_open_orders(symbol)
        )

    def submit_protective_stop_loss(self, symbol: str, qty: float, stop_price: float) -> Order:
        """Legt eine eigenstaendige Stop-Loss-Order nach, wenn eine offene
        Position keine aktive mehr hat. GTC (siehe submit_bracket_buy),
        damit sie nicht auf dieselbe Weise wieder verschwinden kann.
        """
        order_request = StopOrderRequest(
            symbol=symbol,
            qty=qty,
            side=OrderSide.SELL,
            time_in_force=TimeInForce.GTC,
            stop_price=stop_price,
        )
        try:
            return self._client.submit_order(order_request)
        except APIError as exc:
            raise OrderExecutionError(f"Failed to submit protective stop-loss for {symbol}: {exc}") from exc

    def _cancel_open_orders(self, symbol: str) -> None:
        """Cancels every open order for a symbol -- in particular the
        stop-loss/take-profit legs left over from a bracket buy -- and polls
        until Alpaca confirms none are left (or the retry budget runs out).
        """
        open_orders = self._get_open_orders(symbol)
        if not open_orders:
            return

        for order in open_orders:
            try:
                self._client.cancel_order_by_id(order.id)
            except APIError as exc:
                # 404/409/422 -> order already filled/canceled between the
                # fetch above and this call; nothing left to do for it.
                if getattr(exc, "status_code", None) not in (404, 409, 422):
                    raise OrderExecutionError(
                        f"Failed to cancel order {order.id} for {symbol}: {exc}"
                    ) from exc

        for _ in range(self._cancel_poll_attempts):
            if not self._get_open_orders(symbol):
                return
            time.sleep(self._cancel_poll_interval_seconds)

        remaining = self._get_open_orders(symbol)
        if remaining:
            logger.warning(
                "%d order(s) for %s still open after cancel + %d retries — attempting close anyway",
                len(remaining),
                symbol,
                self._cancel_poll_attempts,
            )

    def close_position(self, symbol: str) -> Order:
        self._cancel_open_orders(symbol)

        last_error: APIError | None = None
        for attempt in range(self._close_retry_attempts):
            try:
                return self._client.close_position(symbol)
            except APIError as exc:
                last_error = exc
                is_last_attempt = attempt == self._close_retry_attempts - 1
                if "insufficient qty" in str(exc).lower() and not is_last_attempt:
                    logger.warning(
                        "close_position(%s) hit 'insufficient qty' (bracket legs likely not yet "
                        "released) — retrying (%d/%d)",
                        symbol,
                        attempt + 1,
                        self._close_retry_attempts,
                    )
                    time.sleep(self._close_retry_backoff_seconds * (attempt + 1))
                    continue
                raise OrderExecutionError(f"Failed to close position for {symbol}: {exc}") from exc

        raise OrderExecutionError(f"Failed to close position for {symbol}: {last_error}")
