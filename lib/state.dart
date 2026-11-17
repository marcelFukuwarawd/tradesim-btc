// state.dart — Controlador global do TradeSim BTC.
// • Alimenta o gráfico com candles reais de BTC/USDT (API pública Binance)
// • Executa a estratégia balanceada nas velas de 5m FECHADAS
// • Recupera o "catch-up" determinístico das velas perdidas ao abrir o app
// • Agenda/atualiza a notificação diária das 21h e gera o relatório
// • Atualiza o widget 5x5 da tela inicial
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'api.dart';
import 'db.dart';
import 'engine.dart';
import 'fmt.dart';
import 'notifications.dart';

enum FeedMode { connecting, live, offline }

class AppController extends ChangeNotifier {
  final BinanceClient _api = BinanceClient();

  // ---- estado visível na UI
  FeedMode mode = FeedMode.connecting;
  String? feedError;
  List<Candle> candles5m = [];
  Ticker24h? ticker;
  bool autoTrade = true;
  double riskPct = 0.02;
  double atrStopMult = 1.8;
  double atrTpMult = 3.0;

  Portfolio portfolio = Portfolio();
  int lastProcessed5m = 0;

  double todayRealizedPnl = 0;
  int todayTradeCount = 0;
  int todayWins = 0;
  int totalTrades = 0;
  int totalWins = 0;

  bool _ticking = false;
  bool _initialized = false;
  Timer? _timer;
  Strategy? _strategy;

  static const int chartWindow = 150;

  bool get initialized => _initialized;
  bool get inPosition => portfolio.open;
  double get lastPrice =>
      ticker?.last ?? (candles5m.isNotEmpty ? candles5m.last.close : 0);
  double get equity => portfolio.equity(lastPrice);
  double get unrealizedPnl => portfolio.unrealizedPnl(lastPrice);
  double get totalPnl => equity - Portfolio.initialCash;
  double get roiPct => totalPnl / Portfolio.initialCash * 100;
  double get todayPnl => todayRealizedPnl + (inPosition ? unrealizedPnl : 0);

  // ------------------------------------------------------------ init
  Future<void> init() async {
    if (_initialized) return;
    await _loadState();
    await NotificationService.init();
    await NotificationService.requestPermission();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    await refresh(forceBootstrap: true);
    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadState() async {
    final acc = AccountState.decode(await Db.I.getMeta(kAccountMetaKey));
    if (acc != null) {
      portfolio = acc.portfolio;
      lastProcessed5m = acc.lastProcessed5mMs;
    }
    autoTrade = await Db.I.getMetaBool('auto_trade') ?? true;
    riskPct = (await Db.I.getMetaDouble('risk_pct')) ?? 0.02;
    atrStopMult = (await Db.I.getMetaDouble('atr_stop')) ?? 1.8;
    atrTpMult = (await Db.I.getMetaDouble('atr_tp')) ?? 3.0;
  }

  Future<void> _persistState() async {
    await Db.I.putMeta(
        kAccountMetaKey,
        AccountState(portfolio: portfolio, lastProcessed5mMs: lastProcessed5m)
            .encode());
  }

  StrategyConfig _cfg() => StrategyConfig(
      riskPct: riskPct, atrStopMult: atrStopMult, atrTpMult: atrTpMult);

  int get _nowMs => DateTime.now().toUtc().millisecondsSinceEpoch;

  // ---------------------------------------------------------- refresh
  Future<void> refresh({bool forceBootstrap = false}) async {
    if (_ticking) return;
    _ticking = true;
    try {
      ticker = await _api.ticker24h();

      if (_strategy == null || forceBootstrap) {
        await _bootstrap();
      }

      // Caminho barato: últimas 150 velas — processa as que fecharam desde a última
      final recent = await _api.klines(interval: '5m', limit: chartWindow);
      candles5m = recent;

      // Se ficamos muito tempo offline, a janela não cobre — faz catch-up completo
      final oldestCovered = recent.isNotEmpty ? recent.first.openTime : _nowMs;
      if (lastProcessed5m > 0 && oldestCovered > lastProcessed5m + 5 * 60 * 1000) {
        await _bootstrap(gapOnly: true);
      } else {
        await _processCandles(recent);
      }

      mode = FeedMode.live;
      feedError = null;
      await _refreshTodayPnl();
    } catch (e) {
      mode = FeedMode.offline;
      feedError =
          'Sem acesso à Binance — exibindo gráfico sintético. Trades automáticos pausados até reconectar.';
      if (candles5m.isEmpty) {
        candles5m = SyntheticMarket.recentWindow(chartWindow);
      }
    } finally {
      _ticking = false;
      notifyListeners();
    }
    await _refreshWidget();
    await _rescheduleReportNotification();
    await maybeGenerate21hReport();
  }

  /// Aquece indicadores (sem operar) e executa as velas fechadas pendentes.
  Future<void> _bootstrap({bool gapOnly = false}) async {
    // Primeira execução de todas: parte da vela FECHADA atual (sem retroativos)
    if (lastProcessed5m == 0) {
      final recent = await _api.klines(interval: '5m', limit: 3);
      final closed = recent.where((c) => c.isClosed(_nowMs)).toList();
      if (closed.isNotEmpty) {
        lastProcessed5m = closed.last.openTime;
        await _persistState();
      }
    }

    if (!gapOnly) {
      final warm =
          await _api.klines(interval: '5m', limit: 300, endTime: lastProcessed5m + 1);
      _strategy = Strategy(_cfg(), portfolio);
      for (final c in warm) {
        _strategy!.onCandle(c, 0, false, _nowMs);
      }
    }

    // Segurança: sem referência de partida, não pagina anos de candles
    if (lastProcessed5m <= 0) {
      await _persistState();
      return;
    }

    final gap = await _api.klinesSince(interval: '5m', startTime: lastProcessed5m + 1);
    await _processCandles(gap);
    await _persistState();
  }

  Future<void> _processCandles(List<Candle> candles) async {
    _strategy ??= Strategy(_cfg(), portfolio);
    var executed = 0;
    for (final c in candles) {
      if (c.openTime <= lastProcessed5m) continue;
      if (!c.isClosed(_nowMs)) continue;
      _strategy!.onCandle(c, executed, autoTrade, _nowMs);
      lastProcessed5m = c.openTime;
      executed++;
    }
    if (executed > 0 || _strategy!.newTrades.isNotEmpty) {
      for (final t in _strategy!.newTrades) {
        await Db.I.insertTrade(t);
      }
      _strategy!.newTrades.clear();
      await _persistState();
    }
  }

  // --------------------------------------------------- P&L de hoje
  Future<void> _refreshTodayPnl() async {
    final now = DateTime.now();
    final (from, to) = localDayRangeMs(now);
    final today = await Db.I.tradesBetween(from, to);
    todayRealizedPnl = today.fold<double>(0, (a, t) => a + t.pnl);
    todayTradeCount = today.length;
    todayWins = today.where((t) => t.pnl > 0).length;
    totalTrades = await Db.I.tradeCount();
    totalWins = await Db.I.winCount();
  }

  // --------------------------------------- fechamento manual da posição
  Future<Trade?> closePosition() async {
    if (!portfolio.open || candles5m.isEmpty) return null;
    final last = candles5m.last;
    final exitPx = last.close * (1 - StrategyConfig.slip);
    final proceeds = portfolio.qty * exitPx;
    final fee = proceeds * StrategyConfig.feeRate;
    final cost = portfolio.entryCost();
    portfolio.cash += proceeds - fee;
    final pnl = proceeds - fee - cost;
    final trade = Trade(
      entryTime: portfolio.entryTime,
      exitTime: _nowMs,
      qty: portfolio.qty,
      entryPrice: portfolio.entryPrice,
      exitPrice: exitPx,
      pnl: pnl,
      pnlPct: cost == 0 ? 0 : pnl / cost * 100,
      reason: 'Fechamento manual',
    );
    portfolio.qty = 0;
    portfolio.open = false;
    portfolio.entryPrice = 0;
    portfolio.entryAtr = 0;
    await Db.I.insertTrade(trade);
    await _persistState();
    // ressincroniza a estratégia viva com o novo portfolio
    _strategy = null;
    await _refreshTodayPnl();
    notifyListeners();
    await _refreshWidget();
    return trade;
  }

  // ------------------------------------------------------- config
  Future<void> setAutoTrade(bool v) async {
    autoTrade = v;
    await Db.I.putMetaBool('auto_trade', v);
    notifyListeners();
  }

  Future<void> setRiskPct(double v) async {
    riskPct = v;
    _strategy = null; // reaplica ao próximo bootstrap
    await Db.I.putMetaDouble('risk_pct', v);
    notifyListeners();
  }

  Future<void> setAtrStopMult(double v) async {
    atrStopMult = v;
    _strategy = null;
    await Db.I.putMetaDouble('atr_stop', v);
    notifyListeners();
  }

  Future<void> setAtrTpMult(double v) async {
    atrTpMult = v;
    _strategy = null;
    await Db.I.putMetaDouble('atr_tp', v);
    notifyListeners();
  }

  Future<void> resetSimulation() async {
    await Db.I.clearAll();
    portfolio = Portfolio();
    lastProcessed5m = 0;
    todayRealizedPnl = 0;
    todayTradeCount = 0;
    todayWins = 0;
    candles5m = [];
    ticker = null;
    _strategy = null;
    autoTrade = true;
    riskPct = 0.02;
    atrStopMult = 1.8;
    atrTpMult = 3.0;
    mode = FeedMode.connecting;
    notifyListeners();
    await refresh(forceBootstrap: true);
  }

  // ----------------------------------------- relatório das 21h (local)
  /// Gera o relatório se já passaram das 21h e ainda não existe hoje.
  Future<void> maybeGenerate21hReport() async {
    final now = DateTime.now();
    if (now.hour < 21) return;
    final key = reportDateKey(now);
    final last = await Db.I.getMeta('last_report_date');
    if (last == key) return;
    await generateDailyReport(now, notify: true);
    await Db.I.putMeta('last_report_date', key);
  }

  /// Gera (ou regenera) o relatório do dia [now] e salva no banco.
  Future<ReportRow> generateDailyReport(DateTime now, {bool notify = false}) async {
    final key = reportDateKey(now);
    final (from, to) = localDayRangeMs(now);
    final trades = await Db.I.tradesBetween(from, to);
    final realized = trades.fold<double>(0, (a, t) => a + t.pnl);
    final wins = trades.where((t) => t.pnl > 0).length;
    final losses = trades.length - wins;
    final endCash = portfolio.cash;
    final mark = lastPrice > 0 ? lastPrice : endCash;
    final endEquity = portfolio.cash + portfolio.qty * mark;
    // Aproximação: denominador = patrimônio antes do P&L realizado de hoje
    final base = (endEquity - realized);
    final roi = base > 0 ? realized / base * 100 : 0.0;

    final row = ReportRow(
      date: key,
      realizedPnl: realized,
      trades: trades.length,
      wins: wins,
      losses: losses,
      endCash: endCash,
      endEquity: endEquity,
      roiPct: roi,
      createdTs: DateTime.now().millisecondsSinceEpoch,
    );
    await Db.I.upsertReport(row);
    if (notify) {
      await NotificationService.showNow(
        'TradeSim BTC — Relatório das 21h',
        reportBody(row),
      );
    }
    notifyListeners();
    return row;
  }

  String reportBody(ReportRow r) {
    final pnl = fmtUsd(r.realizedPnl, sign: true);
    final roi = fmtPct(r.roiPct);
    final cash = fmtUsd(r.endCash);
    if (r.trades == 0) {
      return 'Hoje não houve operações fechadas. Caixa: $cash.';
    }
    return 'Hoje: $pnl ($roi) · ${r.trades} ${r.trades == 1 ? 'trade' : 'trades'} '
        '(${r.wins}V/${r.losses}D) · Caixa: $cash';
  }

  Future<String> pendingNotificationBody() async {
    final now = DateTime.now();
    final (from, to) = localDayRangeMs(now);
    final trades = await Db.I.tradesBetween(from, to);
    final realized = trades.fold<double>(0, (a, t) => a + t.pnl);
    final wins = trades.where((t) => t.pnl > 0).length;
    final endEquity = portfolio.cash + portfolio.qty * (lastPrice > 0 ? lastPrice : portfolio.cash);
    final base = endEquity - realized;
    final roi = base > 0 ? realized / base * 100 : 0.0;
    final body =
        'Hoje até agora: ${fmtUsd(realized, sign: true)} (${fmtPct(roi)}) · '
        '${trades.length} trades (${wins}V/${trades.length - wins}D) · '
        'Caixa: ${fmtUsd(portfolio.cash)}';
    return body;
  }

  Future<void> _rescheduleReportNotification() async {
    try {
      final body = await pendingNotificationBody();
      await NotificationService.scheduleDailyReport(body);
    } catch (_) {
      // Pode falhar sem permissão — o app avisa na tela de Ajustes.
    }
  }

  // ------------------------------------------------------------ widget
  Future<void> _refreshWidget() async {
    try {
      final priceTxt = ticker != null ? fmtUsd(ticker!.last) : '—';
      final posTxt = portfolio.open
          ? 'Comprado ${fmtBtc(portfolio.qty)} BTC @ ${fmtUsd(portfolio.entryPrice)}'
          : 'Zerado — aguardando sinal';
      final pnlTxt = 'Hoje: ${fmtUsd(todayPnl, sign: true)}';
      final cashTxt = 'Caixa: ${fmtUsd(portfolio.cash)}';
      final roiTxt = 'ROI total: ${fmtPct(roiPct)} · Alvo 21h';
      final now = DateTime.now();
      final upd =
          'Atualizado ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      await HomeWidget.saveWidgetData<String>('price', priceTxt);
      await HomeWidget.saveWidgetData<String>('position', posTxt);
      await HomeWidget.saveWidgetData<String>('pnl_today', pnlTxt);
      await HomeWidget.saveWidgetData<String>('cash', cashTxt);
      await HomeWidget.saveWidgetData<String>('roi', roiTxt);
      await HomeWidget.saveWidgetData<String>('updated', upd);
      await HomeWidget.updateWidget(
        name: 'TradeWidgetProvider',
        androidName: 'TradeWidgetProvider',
        qualifiedAndroidName: 'com.tradesim.btc_trader_sim.TradeWidgetProvider',
      );
    } catch (_) {
      // Widget ainda não adicionado à tela inicial — sem problema.
    }
  }

  // ---------------------------------------------------------- backtest
  /// Roda a estratégia nos últimos 90 dias (1h). Prefere dados reais da Binance
  /// (cacheados em SQLite); se indisponível, usa a série sintética offline.
  Future<BacktestResult> runBacktest() async {
    List<Candle> series;
    String source;
    try {
      final start = _nowMs - 90 * 24 * 3600 * 1000;
      final fresh = await _api.klinesSince(interval: '1h', startTime: start);
      if (fresh.length >= 200) {
        await Db.I.cacheCandles1h(fresh);
        series = fresh;
        source = 'Binance · 1h · últimos 90 dias';
      } else {
        final cached = await Db.I.cachedCandles1h();
        if (cached.length >= 200) {
          series = cached;
          source = 'Cache local (sem rede) · 1h · 90 dias';
        } else {
          series = resample(SyntheticMarket.lastDays(90), 12);
          source = 'Sintético offline (sem cache ainda) · 1h · 90 dias';
        }
      }
    } catch (_) {
      final cached = await Db.I.cachedCandles1h();
      if (cached.length >= 200) {
        series = cached;
        source = 'Cache local (offline) · 1h · 90 dias';
      } else {
        series = resample(SyntheticMarket.lastDays(90), 12);
        source = 'Sintético offline · 1h · 90 dias';
      }
    }
    return BacktestResult.compute(series, _cfg(), source);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api.dispose();
    super.dispose();
  }
}
