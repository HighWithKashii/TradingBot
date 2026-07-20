"""Position sizing, stop-loss / take-profit price calculation and the daily
loss limit circuit breaker. Kept isolated from order execution so the sizing
rules or loss limit can be swapped without touching the Alpaca-facing code.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from trading_bot.config import Config


@dataclass
class BracketPrices:
    stop_loss: float
    take_profit: float


class RiskManager:
    def __init__(self, config: Config):
        self._config = config
        self._current_day: date | None = None
        self._starting_equity: float = 0.0
        self._realized_pnl_today: float = 0.0

    def start_new_day_if_needed(self, today: date, equity: float) -> None:
        if self._current_day != today:
            self._current_day = today
            self._starting_equity = equity
            self._realized_pnl_today = 0.0

    def register_realized_pnl(self, pnl: float) -> None:
        self._realized_pnl_today += pnl

    @property
    def realized_pnl_today(self) -> float:
        return self._realized_pnl_today

    def daily_loss_limit_hit(self) -> bool:
        if self._starting_equity <= 0:
            return False
        max_loss = self._starting_equity * (self._config.max_daily_loss_pct / 100)
        return self._realized_pnl_today <= -max_loss

    def calculate_position_size(self, equity: float, buying_power: float, price: float) -> int:
        """Fixed fractional sizing: at most position_size_pct of equity per trade,
        never exceeding available buying power.
        """
        if price <= 0:
            return 0
        capital_at_risk = equity * (self._config.position_size_pct / 100)
        capital_at_risk = min(capital_at_risk, buying_power)
        qty = int(capital_at_risk // price)
        return max(qty, 0)

    def calculate_bracket_prices(self, entry_price: float) -> BracketPrices:
        stop_loss = round(entry_price * (1 - self._config.stop_loss_pct / 100), 2)
        take_profit = round(entry_price * (1 + self._config.take_profit_pct / 100), 2)
        return BracketPrices(stop_loss=stop_loss, take_profit=take_profit)
