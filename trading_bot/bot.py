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

import pandas as pd

from trading_bot.config import Config
from trading_bot.data_feed import MarketDataFeed
from trading_bot.notifier import TradeFailureNotifier
from trading_bot.order_executor import (
    OrderExecutionError,
    OrderExecutor,
    StopPriceAlreadyBreachedError,
    is_orphaned_take_profit_order,
)
from trading_bot.risk_manager import BracketPrices, RiskManager, round_to_valid_tick
from trading_bot.strategy import (
    Action,
    combine_with_pattern_signal,
    compute_indicators,
    generate_pattern_signal_from_config,
    generate_signal,
)
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
    # Sicherheitspuffer fuer nachgelegte Stop-Loss-Orders: der Stop wird nie
    # hoeher als (aktueller Kurs * (1 - Puffer)) angesetzt, selbst wenn der
    # eigentlich vorgesehene Stop (aus dem Entry-Preis berechnet) hoeher
    # laege -- verhindert, dass eine kleine Verzoegerung zwischen dieser
    # Pruefung und dem eigentlichen Order-Submit erneut zu Alpacas
    # "stop price must be less than current price" fuehrt (siehe
    # StopPriceAlreadyBreachedError fuer den Fall, dass der Kurs trotzdem
    # schon durchgebrochen ist).
    _PROTECTIVE_STOP_BUFFER_PCT = 0.1

    def __init__(
        self,
        config: Config,
        data_feed: MarketDataFeed,
        executor: OrderExecutor,
        risk_manager: RiskManager,
        trade_logger: TradeLogger,
        failure_notifier: TradeFailureNotifier | None = None,
    ):
        self._config = config
        self._data_feed = data_feed
        self._executor = executor
        self._risk_manager = risk_manager
        self._trade_logger = trade_logger
        self._failure_notifier = failure_notifier or TradeFailureNotifier(config)
        # Vom Start-Backfill (siehe warm_up_with_backfill) fuer den ersten
        # run_cycle() vorgeladene Bars, damit der allererste Zyklus nicht
        # nochmal dieselben Daten frisch abruft. Wird nach einmaligem
        # Gebrauch verworfen; siehe run_cycle() fuer die Freshness-Pruefung.
        self._prefetched_bars: dict[str, pd.DataFrame] | None = None
        self._prefetched_bars_at: float | None = None

    def warm_up_with_backfill(self) -> None:
        """Laedt beim Start genug historische Bars pro Watchlist-Symbol vor,
        damit der Bot direkt im ersten Zyklus vollstaendige Indikatoren
        berechnen kann, statt tage-/wochenlang nur "nicht genug Historie"
        zu melden, waehrend Live-Daten erst nachgesammelt werden.
        """
        config = self._config
        watchlist = config.watchlist
        limit = config.min_bars_required + 10
        logger.info(
            "Backfill: lade historische %s-Bars fuer %d Symbole (min. %d Bars je Symbol benoetigt)...",
            config.timeframe,
            len(watchlist),
            config.min_bars_required,
        )
        backfill_start = time.monotonic()
        results = self._data_feed.backfill_bars(watchlist, limit=limit)
        elapsed = time.monotonic() - backfill_start

        sufficient = [s for s in watchlist if len(results.get(s, [])) >= config.min_bars_required]
        partial = [
            s for s in watchlist if s in results and 0 < len(results[s]) < config.min_bars_required
        ]
        failed = [s for s in watchlist if s not in results or len(results[s]) == 0]

        logger.info(
            "Backfill abgeschlossen in %.1fs: %d/%d Symbole mit vollstaendiger Historie, "
            "%d mit unvollstaendiger Historie, %d fehlgeschlagen.",
            elapsed,
            len(sufficient),
            len(watchlist),
            len(partial),
            len(failed),
        )
        if partial:
            logger.warning(
                "Unvollstaendige Backfill-Historie (noch nicht handelbar bis genug Live-Bars dazukommen): %s",
                ", ".join(partial[:20]) + (", ..." if len(partial) > 20 else ""),
            )
        if failed:
            logger.warning(
                "Backfill fehlgeschlagen fuer: %s",
                ", ".join(failed[:20]) + (", ..." if len(failed) > 20 else ""),
            )

        self._prefetched_bars = results
        self._prefetched_bars_at = time.monotonic()

    def run_forever(self) -> None:
        config = self._config
        source = "Nasdaq-100" if config.use_nasdaq100 else "fixed list"
        logger.info(
            "Starting bot (%s trading) — watchlist: %d symbols (%s), interval=%s min",
            "paper" if config.paper else "LIVE",
            len(config.watchlist),
            source,
            config.check_interval_minutes,
        )
        logger.info(
            "Trading mode: %s | timeframe=%s SMA=%d/%d RSI=%d | "
            "position_size=%.1f%% stop_loss=%.1f%% take_profit=%.1f%% max_daily_loss=%.1f%%",
            config.trading_mode.upper(),
            config.timeframe,
            config.sma_fast,
            config.sma_slow,
            config.rsi_period,
            config.position_size_pct,
            config.stop_loss_pct,
            config.take_profit_pct,
            config.max_daily_loss_pct,
        )
        try:
            self.warm_up_with_backfill()
        except Exception:
            logger.exception("Backfill beim Start fehlgeschlagen -- Bot startet trotzdem, Indikatoren werden ueber die naechsten Live-Zyklen nachgesammelt.")
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

        self._check_position_protection(positions)

        # Erster Zyklus nach dem Start: die vom Backfill vorgeladenen Bars
        # wiederverwenden statt dieselben Daten nochmal abzurufen -- aber
        # nur, wenn der Backfill nicht laenger als zwei Scan-Intervalle her
        # ist (z.B. Deploy ausserhalb der Handelszeit, Markt oeffnet erst
        # Stunden/Tage spaeter -> dann lieber frisch abrufen statt veraltete
        # Bars zu verwenden).
        max_prefetch_age = 2 * self._config.check_interval_minutes * 60
        if self._prefetched_bars is not None and (time.monotonic() - self._prefetched_bars_at) < max_prefetch_age:
            bars_by_symbol = self._prefetched_bars
        else:
            bars_by_symbol = self._data_feed.get_bars_batch(watchlist, limit=self._config.min_bars_required + 10)
        self._prefetched_bars = None
        self._prefetched_bars_at = None

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

    @staticmethod
    def _positive_float(value, default: float) -> float:
        """Wandelt ein Alpaca-Positionsfeld (kommt als String) in float um,
        mit Fallback auf `default` -- aber NICHT per `value or default`,
        denn ein nicht-leerer String wie "0" ist in Python truthy, `or`
        wuerde den Fallback also NIE verwenden, selbst wenn der geparste
        Wert tatsaechlich 0 ist. Genau das hat zuvor dazu gefuehrt, dass
        `qty_available="0"` als qty=0 an submit_protective_stop_loss ging
        (Alpaca: "qty must be > 0"), obwohl die Position noch offen war
        und `qty` (die Gesamtmenge) als Fallback haette greifen sollen.
        """
        try:
            parsed = float(value) if value is not None else 0.0
        except (TypeError, ValueError):
            parsed = 0.0
        return parsed if parsed > 0 else default

    def _market_sell_fallback(self, symbol: str, detail: str, reason: str) -> str | None:
        """Schliesst eine Position per Market-Sell, nachdem eine Stop-Order
        wegen bereits durchbrochenem Kurs abgelehnt wurde (siehe
        StopPriceAlreadyBreachedError) -- egal ob auf dem normalen Nachlege-
        Pfad oder nach der Reparatur einer verwaisten Take-Profit-Order.
        Gibt den erweiterten `detail`-Text bei Erfolg zurueck; bei
        Fehlschlag wurde bereits ein KRITISCH-Alert verschickt/geloggt und
        None zurueckgegeben -- der Aufrufer soll dann direkt `continue`n.
        """
        try:
            closed_order = self._executor.close_position(symbol)
        except OrderExecutionError as close_exc:
            detail += f" KRITISCH: {reason} UND automatischer Market-Sell fehlgeschlagen: {close_exc}"
            logger.critical(
                "KRITISCH: %s bleibt UNGESCHUETZT -- %s UND Market-Sell fehlgeschlagen: %s",
                symbol,
                reason,
                close_exc,
            )
            self._failure_notifier.notify_unprotected_position(symbol, detail, critical=True)
            self._trade_logger.log(symbol=symbol, action="ALERT", reason=detail, status="critical")
            return None

        # Nur hier angekommen, wenn close_position() ohne Fehler eine von
        # Alpaca angenommene Order zurueckgegeben hat -- der "geschlossen"-
        # Erfolg wird also durch die tatsaechliche Order-Response belegt
        # (Order-ID + Status), nicht bloss dadurch, dass dieser Pfad
        # erreicht wurde.
        detail += f" {reason} -> Position per Market-Sell geschlossen (Order {closed_order.id}, Status {closed_order.status})."
        logger.info(
            "%s per Market-Sell geschlossen (%s; Order-ID %s, Status %s).",
            symbol,
            reason,
            closed_order.id,
            closed_order.status,
        )
        return detail

    def _check_position_protection(self, positions: dict) -> None:
        """Sicherheitsnetz: prueft bei jedem Zyklus, ob jede offene Position
        noch eine aktive Stop-Loss-Order hat. Alpaca kann beide Bracket-Legs
        gleichzeitig verwerfen (z.B. eine am Handelsschluss nicht gefuellte
        Take-Profit-Limit-Order laeuft ab und storniert ueber die OCO-
        Verknuepfung automatisch auch den Stop-Loss) -- die Position liefe
        danach bis zum naechsten regulaeren Exit-Signal komplett ungeschuetzt
        weiter, ohne dass das sonst irgendwo auffaellt. Legt bei Bedarf
        automatisch eine neue Stop-Loss-Order nach und alarmiert per Telegram.

        Sonderfaelle neben dem einfachen "Stop nachlegen"-Pfad:
        - Position mit Menge <= 0 ("Phantom-Position"): wird VOR dem
          eigentlichen Pruef-Loop komplett rausgefiltert, ganz ohne
          API-Aufruf fuer sie (siehe _positive_float's Docstring fuer den
          verwandten, aber separaten Bug, der frueher qty_available="0"
          betraf -- DIESER Filter hier prueft die Gesamtmenge `qty`, nicht
          `qty_available`, und war fuer sich genommen bereits korrekt).
        - Die Stop-Preis-Berechnung selbst schlaegt fehl (z.B. unerwartete/
          fehlende Positionsdaten): eigener try/except NUR um die
          Berechnung, damit ein Fehler hier klar als "Berechnung
          fehlgeschlagen" gemeldet wird -- und NICHT stillschweigend in
          einen der spaeteren Erfolgspfade durchrutscht.
        - Die Aktien sind bereits durch eine andere offene Order blockiert
          (z.B. eine verwaiste Take-Profit-Order ohne zugehoeriges
          Stop-Loss-Leg, siehe is_orphaned_take_profit_order): eine blind
          versuchte neue Stop-Order wuerde hier zwangslaeufig mit
          "insufficient qty available for order" scheitern und sich jeden
          Zyklus identisch wiederholen, ohne das eigentliche Problem
          anzugehen. Ist die blockierende Order eindeutig als verwaiste
          Take-Profit-Order erkennbar, wird sie storniert und ein sauberes
          neues Stop-Loss+Take-Profit-Paar (OCO) nachgelegt. Ist NICHT
          eindeutig erkennbar, ob eine blockierende Order gefahrlos
          storniert werden darf (z.B. eine gerade laufende reguläre
          Exit-Order), wird NICHTS automatisch angefasst, sondern nur klar
          alarmiert, was blockiert.
        - Der Kurs ist bereits unter den berechneten Stop-Preis gefallen ->
          Alpaca lehnt die neue Stop-Order ab (StopPriceAlreadyBreachedError).
          Die Position wird dann per Market-Sell geschlossen -- der
          "geschlossen"-Log/-Alert wird aber erst geschrieben, NACHDEM
          close_position() tatsaechlich eine von Alpaca angenommene Order
          zurueckgegeben hat (kein Fehler = Alpaca hat akzeptiert), nicht
          schon dafuer, dass der Code-Pfad erreicht wurde. Schlaegt auch
          der Market-Sell fehl, gibt es einen eigenen "KRITISCH"-Alert
          statt der normalen Warnung.
        """
        to_check, phantom_symbols = {}, []
        for symbol, position in positions.items():
            if float(position.qty) <= 0:
                phantom_symbols.append(symbol)
                continue
            to_check[symbol] = position

        if phantom_symbols:
            # get_all_positions() sollte eine vollstaendig geschlossene
            # Position eigentlich gar nicht mehr zurueckliefern -- passiert
            # das trotzdem, ist die wahrscheinlichste Erklaerung ein kurzes
            # Timing-Fenster zwischen einem gerade gefuellten Verkauf und dem
            # naechsten Positions-Snapshot (oder kurzzeitig veraltete Daten
            # auf Alpacas Seite). Fuer eine Menge von 0 gibt es nichts zu
            # schuetzen -- das Ueberspringen selbst ist bereits die
            # ausreichende Absicherung, kein API-Aufruf noetig.
            logger.debug(
                "Stop-Loss-Pruefung: %d Position(en) mit Menge 0 uebersprungen (bereits geschlossen): %s",
                len(phantom_symbols),
                ", ".join(phantom_symbols),
            )

        for symbol, position in to_check.items():
            try:
                if self._executor.has_active_stop_loss(symbol):
                    continue
            except OrderExecutionError as exc:
                logger.error("Konnte Stop-Loss-Status fuer %s nicht pruefen: %s", symbol, exc)
                continue

            try:
                qty = self._positive_float(getattr(position, "qty_available", None), default=float(position.qty))
                entry_price = float(position.avg_entry_price)
                current_price = self._positive_float(getattr(position, "current_price", None), default=entry_price)
                bracket_prices = self._risk_manager.calculate_bracket_prices(entry_price)
                max_valid_stop = current_price * (1 - self._PROTECTIVE_STOP_BUFFER_PCT / 100)
                stop_price = round_to_valid_tick(min(bracket_prices.stop_loss, max_valid_stop))
            except Exception as exc:
                detail = f"Stop-Preis-Berechnung fuer {symbol} fehlgeschlagen: {exc}"
                logger.critical(
                    "KRITISCH: %s bleibt UNGESCHUETZT -- Stop-Preis-Berechnung fehlgeschlagen, kein "
                    "Nachlege- oder Market-Sell-Versuch unternommen: %s",
                    symbol,
                    exc,
                )
                self._failure_notifier.notify_unprotected_position(symbol, detail, critical=True)
                self._trade_logger.log(symbol=symbol, action="ALERT", reason=detail, status="critical")
                continue

            detail = f"Position: {qty:g} Stk. @ Entry {entry_price:.2f}."

            try:
                blocking_orders = self._executor.get_open_orders(symbol)
            except OrderExecutionError as exc:
                logger.error("Konnte offene Orders fuer %s nicht abfragen: %s", symbol, exc)
                continue

            if blocking_orders:
                self._repair_blocked_position(symbol, position, blocking_orders, stop_price, bracket_prices, detail)
                continue

            logger.warning(
                f"{Fore.RED}UNGESCHUETZTE POSITION: %s (%.0f Stk.) hat keine aktive Stop-Loss-Order! "
                f"Versuche, automatisch eine neue @ %.2f nachzulegen.{Style.RESET_ALL}",
                symbol,
                qty,
                stop_price,
            )
            try:
                self._executor.submit_protective_stop_loss(symbol, qty, stop_price)
            except StopPriceAlreadyBreachedError as exc:
                logger.warning(
                    "%s: Stop-Preis bereits vom aktuellen Kurs durchbrochen (%s) -- schliesse Position "
                    "sofort per Market-Sell, statt weiter eine ungueltige Stop-Order zu versuchen.",
                    symbol,
                    exc,
                )
                detail = self._market_sell_fallback(symbol, detail, "Stop-Preis bereits durchbrochen")
                if detail is None:
                    continue
            except OrderExecutionError as exc:
                detail += f" AUTOMATISCHES NACHLEGEN FEHLGESCHLAGEN: {exc}"
                logger.error("Konnte Stop-Loss fuer %s NICHT automatisch nachlegen: %s", symbol, exc)
            else:
                detail += f" Neue Stop-Loss-Order @ {stop_price:.2f} automatisch nachgelegt."
                logger.info("Stop-Loss fuer %s @ %.2f erfolgreich nachgelegt.", symbol, stop_price)

            self._failure_notifier.notify_unprotected_position(symbol, detail)
            self._trade_logger.log(symbol=symbol, action="ALERT", reason=detail, status="warning")

    def _repair_blocked_position(
        self, symbol: str, position, blocking_orders: list, stop_price: float, bracket_prices: BracketPrices, detail: str
    ) -> None:
        """Eine ungeschuetzte Position, deren Aktien bereits durch mindestens
        eine andere offene Order gebunden sind (`blocking_orders`) -- eine
        blind versuchte neue Stop-Order wuerde hier zwangslaeufig mit
        Alpacas "insufficient qty available for order" scheitern.

        Sind ALLE blockierenden Orders eindeutig verwaiste Take-Profit-Legs
        (siehe is_orphaned_take_profit_order), werden sie storniert und ein
        sauberes neues Stop-Loss+Take-Profit-Paar (OCO) fuer die volle,
        jetzt wieder freie Menge nachgelegt. Ist auch nur EINE blockierende
        Order nicht eindeutig als solche erkennbar (z.B. eine gerade
        laufende reguläre Exit-Order), wird GAR NICHTS automatisch
        angefasst -- auch die eindeutigen Waisen nicht -- sondern nur klar
        alarmiert, was blockiert und dass hier manuell geschaut werden muss.
        """
        unrecognized = [o for o in blocking_orders if not is_orphaned_take_profit_order(o)]
        if unrecognized:
            order_descr = "; ".join(
                f"{o.id} ({getattr(o.type, 'value', o.type)}/{getattr(o.order_class, 'value', o.order_class)}/"
                f"{getattr(o.status, 'value', o.status)}, seit {o.created_at})"
                for o in unrecognized
            )
            detail += (
                f" {len(unrecognized)} offene Order(n) blockieren die Aktien, nicht eindeutig als verwaiste "
                f"Take-Profit-Order erkennbar -- KEINE automatische Aktion, manuelle Pruefung noetig: {order_descr}"
            )
            logger.critical(
                "KRITISCH: %s -- unklare blockierende Order(n), manuelle Pruefung noetig: %s", symbol, order_descr
            )
            self._failure_notifier.notify_unprotected_position(symbol, detail, critical=True)
            self._trade_logger.log(symbol=symbol, action="ALERT", reason=detail, status="critical")
            return

        logger.warning(
            f"{Fore.RED}%s: %d verwaiste Take-Profit-Order(en) ohne zugehoeriges Stop-Loss blockieren die "
            f"Position -- storniere und lege sauberes Exit-Paar nach.{Style.RESET_ALL}",
            symbol,
            len(blocking_orders),
        )
        for orphan in blocking_orders:
            try:
                self._executor.cancel_order(orphan.id, symbol)
                logger.info("Verwaiste Take-Profit-Order %s fuer %s storniert.", orphan.id, symbol)
            except OrderExecutionError as exc:
                detail += f" KRITISCH: verwaiste Take-Profit-Order {orphan.id} konnte nicht storniert werden: {exc}"
                logger.critical(
                    "KRITISCH: %s -- Stornierung der verwaisten Order %s fehlgeschlagen: %s", symbol, orphan.id, exc
                )
                self._failure_notifier.notify_unprotected_position(symbol, detail, critical=True)
                self._trade_logger.log(symbol=symbol, action="ALERT", reason=detail, status="critical")
                return

        full_qty = float(position.qty)
        exit_prices = BracketPrices(stop_loss=stop_price, take_profit=bracket_prices.take_profit)
        try:
            new_order = self._executor.submit_oco_exit(symbol, full_qty, exit_prices)
        except StopPriceAlreadyBreachedError as exc:
            logger.warning(
                "%s: Stop-Preis nach Stornierung der verwaisten Order bereits durchbrochen (%s) -- "
                "schliesse Position sofort per Market-Sell.",
                symbol,
                exc,
            )
            detail = self._market_sell_fallback(
                symbol, detail, "Verwaiste Order storniert, aber Stop-Preis bereits durchbrochen"
            )
            if detail is None:
                return
        except OrderExecutionError as exc:
            detail += f" Verwaiste Order storniert, aber neues Exit-Paar konnte NICHT nachgelegt werden: {exc}"
            logger.critical(
                "KRITISCH: %s bleibt UNGESCHUETZT nach Stornierung -- neues Exit-Paar fehlgeschlagen: %s", symbol, exc
            )
            self._failure_notifier.notify_unprotected_position(symbol, detail, critical=True)
            self._trade_logger.log(symbol=symbol, action="ALERT", reason=detail, status="critical")
            return
        else:
            detail += (
                f" Verwaiste Take-Profit-Order(en) storniert, neues Stop-Loss+Take-Profit-Paar nachgelegt "
                f"(Order {new_order.id})."
            )
            logger.info(
                "%s: verwaistes Take-Profit-Leg repariert, neues Stop-Loss+Take-Profit-Paar nachgelegt (Order-ID %s).",
                symbol,
                new_order.id,
            )

        self._failure_notifier.notify_unprotected_position(symbol, detail)
        self._trade_logger.log(symbol=symbol, action="ALERT", reason=detail, status="warning")

    def _process_symbol(self, symbol, bars, position, equity: float, buying_power: float) -> str:
        try:
            if bars is None or bars.empty:
                self._trade_logger.log(symbol=symbol, action="HOLD", reason="No market data returned.")
                return "HOLD"

            df = compute_indicators(bars, self._config)
            signal = generate_signal(df, self._config, has_open_position=position is not None)
            price = float(df.iloc[-1]["close"])

            if self._config.pattern_enabled:
                # Pattern-Modul laeuft auf den rohen OHLCV-Bars (nicht dem
                # indikator-angereicherten `df`) und kann das Indikator-Signal
                # nur bestaetigen oder auf HOLD zuruecksetzen, nie selbst
                # einen Trade ausloesen -- siehe combine_with_pattern_signal.
                pattern_signal = generate_pattern_signal_from_config(bars, self._config)
                if pattern_signal.direction != "neutral":
                    self._log_pattern_signal(symbol, pattern_signal)
                signal = combine_with_pattern_signal(signal, pattern_signal, self._config)

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

    def _log_pattern_signal(self, symbol: str, pattern_signal) -> None:
        """Eine kompakte Zeile pro tatsaechlich erkanntem Pattern-Signal
        (direction != 'neutral') -- nicht pro gescanntem Symbol, damit das
        bei 100 Symbolen nicht zuspammt. Volle Details landen ohnehin ueber
        die BUY/SELL/HOLD-Zeile in trades.csv.
        """
        logger.info(
            f"{Fore.CYAN}PATTERN {symbol}: {pattern_signal.direction.upper()} "
            f"conf={pattern_signal.confidence:.2f} ({pattern_signal.pattern_type}) — "
            f"{pattern_signal.reason}{Style.RESET_ALL}"
        )

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
        try:
            order = self._executor.submit_bracket_buy(symbol, qty, prices)
        except OrderExecutionError as exc:
            self._failure_notifier.notify_order_failure(symbol, "Bracket Buy Order", exc)
            raise
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
        try:
            order = self._executor.close_position(symbol)
        except OrderExecutionError as exc:
            self._failure_notifier.notify_order_failure(symbol, "Sell Order", exc)
            raise
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
