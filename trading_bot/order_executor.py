"""Everything that talks to Alpaca's trading (order/account) endpoint.

Entries are placed as bracket orders so the stop-loss and take-profit legs
are attached atomically at order submission time. Exits use Alpaca's
close_position, which also cancels the now-orphaned bracket legs.
"""

from __future__ import annotations

from dataclasses import dataclass

from alpaca.common.exceptions import APIError
from alpaca.trading.client import TradingClient
from alpaca.trading.enums import OrderClass, OrderSide, TimeInForce
from alpaca.trading.models import Order, Position, TradeAccount
from alpaca.trading.requests import MarketOrderRequest, StopLossRequest, TakeProfitRequest

from trading_bot.config import Config
from trading_bot.risk_manager import BracketPrices


class OrderExecutionError(Exception):
    pass


class OrderExecutor:
    def __init__(self, config: Config):
        self._client = TradingClient(config.api_key, config.secret_key, paper=config.paper)

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

    def submit_bracket_buy(self, symbol: str, qty: int, prices: BracketPrices) -> Order:
        order_request = MarketOrderRequest(
            symbol=symbol,
            qty=qty,
            side=OrderSide.BUY,
            time_in_force=TimeInForce.DAY,
            order_class=OrderClass.BRACKET,
            take_profit=TakeProfitRequest(limit_price=prices.take_profit),
            stop_loss=StopLossRequest(stop_price=prices.stop_loss),
        )
        try:
            return self._client.submit_order(order_request)
        except APIError as exc:
            raise OrderExecutionError(f"Failed to submit bracket buy order for {symbol}: {exc}") from exc

    def close_position(self, symbol: str) -> Order:
        try:
            return self._client.close_position(symbol)
        except APIError as exc:
            raise OrderExecutionError(f"Failed to close position for {symbol}: {exc}") from exc
