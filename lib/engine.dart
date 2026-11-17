// engine.dart — Motor do simulador TradeSim BTC
//
// Fontes de preço:
//  • Preferência: API PÚBLICA da Binance (sem login/chave) — veja api.dart
//  • Fallback offline: mercado sintético determinístico (este arquivo)
//
// Estratégia "Balanceada" (consenso dos grandes manuais):
//  • Tendência (Murphy): operar somente A FAVOR da tendência — preço acima da EMA-50
//    e gatilho por cruzamento da EMA-9 sobre a EMA-21.
//  • Momento (Wilder): RSI-14 entre 52 e 72 na entrada; saída se RSI > 80.
//  • Stop e alvo por ATR-14 (Wilder): stop = 1.8×ATR, alvo = 3.0×ATR (risco:retorno ≥ 1:1.5).
//  • Dimensionamento por risco (Van Tharp / Schwager): arrisca no máximo 2% do
//    patrimônio por operação; posição limitada por saldo (SEM alavancagem, spot).
//  • Custos reais: taxa de 0.1% (taker, padrão Binance) + 0.05% de slippage por lado.
import 'dart:math' as math;

/// ----------------------------------------------------------- candle OHLCV
class Candle {
  final int openTime; // ms UTC (formato Binance)
  final double open, high, low, close, volume;
  const Candle(this.openTime, this.open, this.high, this.low, this.close, this.volume);

  DateTime get ts => DateTime.fromMillisecondsSinceEpoch(openTime, isUtc: true);
  bool isClosed(int nowMs) => openTime + const Duration(minutes: 5).inMilliseconds <= nowMs;

  factory Candle.fromBinanceK(List<dynamic> k) => Candle(
        k[0] as int,
        double.parse(k[1].toString()),
        double.parse(k[2].toString()),
        double.parse(k[3].toString()),
        double.parse(k[4].toString()),
        double.parse(k[5].toString()),
      );
}

/// Reamostra candles (5m → 1h para o backtest).
List<Candle> resample(List<Candle> src, int factor) {
  if (factor <= 1 || src.isEmpty) return List.of(src);
  final out = <Candle>[];
  for (int i = 0; i < src.length; i += factor) {
    final end = math.min(i + factor, src.length);
    final slice = src.sublist(i, end);
    out.add(Candle(
      slice.first.openTime,
      slice.first.open,
      slice.map((c) => c.high).reduce(math.max),
      slice.map((c) => c.low).reduce(math.min),
      slice.last.close,
      slice.fold(0.0, (a, c) => a + c.volume),
    ));
  }
  return out;
}

/// --------------------------------------- RNG determinístico (fallback)
class Mulberry32 {
  int _s;
  Mulberry32(int seed) : _s = (seed & 0x7fffffff) | 1;
  double next() {
    _s = (_s + 0x6D2B79F5) & 0xffffffff;
    int t = _s;
    t = ((t ^ (t >>> 15)) * (1 | t)) & 0xffffffff;
    t = ((t ^ (t >>> 7)) * (61 | t)) & 0xffffffff;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296.0;
  }

  double gaussian() {
    double u = 0, v = 0;
    while (u == 0) {
      u = next();
    }
    while (v == 0) {
      v = next();
    }
    return math.sqrt(-2.0 * math.log(u)) * math.cos(2 * math.pi * v);
  }
}

/// Mercado sintético determinístico — usado SOMENTE quando a Binance está
/// inacessível e não há nada em cache. GBM com troca de regime e saltos.
class SyntheticMarket {
  static const int seed = 20260801;
  static const double startPrice = 60000;
  static final DateTime kGenesis = DateTime.utc(2026, 8, 1);
  static const Duration interval = Duration(minutes: 5);

  int index = -1;
  double close = startPrice;
  double _vol = 0.0045;
  double _drift = 0.00002;
  int _regimeLeft = 0;
  int _shockCandles = 0;
  final Mulberry32 _rng = Mulberry32(seed);

  SyntheticMarket._();
  factory SyntheticMarket.genesis() => SyntheticMarket._();

  Candle nextCandle() {
    if (_regimeLeft <= 0) {
      _regimeLeft = 40 + (_rng.next() * 180).floor(); // 40–220 velas (~3–18h)
      _drift = (_rng.next() - 0.42) * 0.0012;
      _vol = 0.0025 + _rng.next() * 0.006;
      if (_rng.next() < 0.18) _shockCandles = 3 + (_rng.next() * 8).floor();
    }
    _regimeLeft--;
    double shock = 0;
    if (_shockCandles > 0) {
      shock = (_rng.next() - 0.5) * 0.10;
      _shockCandles--;
    }
    final ret = _drift + _vol * _rng.gaussian() + shock;
    final open = close;
    close = math.max(1000, open * (1 + ret));
    final high = math.max(open, close) * (1 + _rng.next() * _vol * 1.6);
    final low = math.min(open, close) * (1 - _rng.next() * _vol * 1.6);
    final volume = 120 + 300 * _vol * 1000 * (0.5 + _rng.next()) + (shock != 0 ? 2500 : 0);
    index++;
    return Candle(kGenesis.millisecondsSinceEpoch + index * interval.inMilliseconds, open, high,
        low, close, volume);
  }

  /// Últimas [count] velas sintéticas alinhadas ao relógio UTC (apenas para exibição).
  static List<Candle> recentWindow(int count) {
    final m = SyntheticMarket.genesis();
    final endSlot = DateTime.now().toUtc().millisecondsSinceEpoch ~/ interval.inMilliseconds;
    final out = <Candle>[];
    for (int guard = 0; guard < 400000; guard++) {
      final c = m.nextCandle();
      out.add(c);
      if (out.length > count) out.removeAt(0);
      if (c.openTime ~/ interval.inMilliseconds >= endSlot) break;
    }
    return out;
  }

  /// Série sintética de [days] dias terminada agora (usada pelo backtest offline).
  static List<Candle> lastDays(int days) {
    final m = SyntheticMarket.genesis();
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final from = nowMs - days * 24 * 3600 * 1000;
    final out = <Candle>[];
    for (int guard = 0; guard < 400000; guard++) {
      final c = m.nextCandle();
      if (c.openTime >= from) out.add(c);
      if (c.openTime >= nowMs) break;
    }
    return out;
  }
}

/// ------------------------------------------------------------ indicadores
class Ema {
  final double period;
  double? _v;
  Ema(this.period);
  double update(double x) {
    final k = 2.0 / (period + 1);
    _v = _v == null ? x : x * k + _v! * (1 - k);
    return _v!;
  }

  double get value => _v ?? double.nan;
}

class Rsi {
  final int period;
  double? _prevClose, _avgGain, _avgLoss;
  int _count = 0;
  double value = 50;
  Rsi(this.period);

  void update(double close) {
    if (_prevClose == null) {
      _prevClose = close;
      return;
    }
    final d = close - _prevClose!;
    _prevClose = close;
    final gain = math.max(d, 0.0), loss = math.max(-d, 0.0);
    if (_count < period) {
      _avgGain = (_avgGain ?? 0) + gain;
      _avgLoss = (_avgLoss ?? 0) + loss;
      _count++;
      if (_count == period) {
        _avgGain = _avgGain! / period;
        _avgLoss = _avgLoss! / period;
        value = _avgLoss == 0 ? 100 : 100 - 100 / (1 + _avgGain! / _avgLoss!);
      }
      return;
    }
    _avgGain = (_avgGain! * (period - 1) + gain) / period;
    _avgLoss = (_avgLoss! * (period - 1) + loss) / period;
    value = _avgLoss == 0 ? 100 : 100 - 100 / (1 + _avgGain! / _avgLoss!);
  }
}

class Atr {
  final int period;
  double? _prevClose, _atr;
  int _count = 0;
  Atr(this.period);
  double get value => _atr ?? 0;

  void update(double high, double low, double close) {
    final tr = _prevClose == null
        ? high - low
        : math.max(high - low, math.max((high - _prevClose!).abs(), (low - _prevClose!).abs()));
    _prevClose = close;
    if (_count < period) {
      _atr = (_atr ?? 0) + tr;
      _count++;
      if (_count == period) _atr = _atr! / period;
      return;
    }
    _atr = (_atr! * (period - 1) + tr) / period;
  }
}

/// -------------------------------------------------------------- modelo de
/// operação fechada (persistida no banco)
class Trade {
  final int? id;
  final int entryTime, exitTime;
  final double qty, entryPrice, exitPrice, pnl, pnlPct;
  final String reason;

  const Trade({
    this.id,
    required this.entryTime,
    required this.exitTime,
    required this.qty,
    required this.entryPrice,
    required this.exitPrice,
    required this.pnl,
    required this.pnlPct,
    required this.reason,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'entry_time': entryTime,
        'exit_time': exitTime,
        'qty': qty,
        'entry_px': entryPrice,
        'exit_px': exitPrice,
        'pnl': pnl,
        'pnl_pct': pnlPct,
        'reason': reason,
      };

  factory Trade.fromMap(Map<String, Object?> m) => Trade(
        id: m['id'] as int?,
        entryTime: m['entry_time'] as int,
        exitTime: m['exit_time'] as int,
        qty: (m['qty'] as num).toDouble(),
        entryPrice: (m['entry_px'] as num).toDouble(),
        exitPrice: (m['exit_px'] as num).toDouble(),
        pnl: (m['pnl'] as num).toDouble(),
        pnlPct: (m['pnl_pct'] as num).toDouble(),
        reason: m['reason'] as String,
      );
}

/// Posição/portfolio (persistido no meta da tabela)
class Portfolio {
  static const double initialCash = 100.0;
  double cash;
  double qty;
  double entryPrice;
  int entryTime;
  double entryAtr;
  bool open;

  Portfolio({
    this.cash = initialCash,
    this.qty = 0,
    this.entryPrice = 0,
    this.entryTime = 0,
    this.entryAtr = 0,
    this.open = false,
  });

  double equity(double price) => cash + qty * price;
  double entryCost() => qty * entryPrice + qty * entryPrice * StrategyConfig.feeRate;
  double unrealizedPnl(double price) => open ? (qty * price * (1 - StrategyConfig.feeRate)) - entryCost() : 0;

  Map<String, Object?> toMap() => {
        'cash': cash,
        'qty': qty,
        'entry_px': entryPrice,
        'entry_time': entryTime,
        'entry_atr': entryAtr,
        'open': open ? 1 : 0,
      };

  factory Portfolio.fromMap(Map<String, Object?> m) => Portfolio(
        cash: (m['cash'] as num).toDouble(),
        qty: (m['qty'] as num?)?.toDouble() ?? 0,
        entryPrice: (m['entry_px'] as num?)?.toDouble() ?? 0,
        entryTime: (m['entry_time'] as num?)?.toInt() ?? 0,
        entryAtr: (m['entry_atr'] as num?)?.toDouble() ?? 0,
        open: ((m['open'] as num?)?.toInt() ?? 0) == 1,
      );
}

/// Parâmetros da estratégia
class StrategyConfig {
  static const double feeRate = 0.001; // 0,1% taker (Binance)
  static const double slip = 0.0005; // 0,05% de slippage por lado

  double riskPct; // fração do patrimônio arriscada por operação (padrão 2%)
  double atrStopMult; // stop em múltiplos de ATR (padrão 1.8)
  double atrTpMult; // alvo em múltiplos de ATR (padrão 3.0)

  StrategyConfig({this.riskPct = 0.02, this.atrStopMult = 1.8, this.atrTpMult = 3.0});
}

/// ------------------------------------------------------------- estratégia
/// Balanceada (seguir tendência + confluência de filtros).
class Strategy {
  final StrategyConfig cfg;
  final Portfolio p;

  final Ema ema9 = Ema(9);
  final Ema ema21 = Ema(21);
  final Ema ema50 = Ema(50);
  final Rsi rsi = Rsi(14);
  final Atr atr = Atr(14);

  double _prevEma9 = double.nan, _prevEma21 = double.nan;
  int candlesSeen = 0;

  double peakEquity;
  double maxDrawdown = 0; // em US$
  double maxDrawdownPct = 0; // % do pico
  final List<double> equityCurve = [];
  final List<Trade> newTrades = [];

  static const int warmupCandles = 60;

  Strategy(this.cfg, this.p) : peakEquity = p.cash;

  /// Alimenta uma vela. [execute]=false apenas aquece indicadores (sem operar).
  void onCandle(Candle c, int index, bool execute, int nowMs) {
    ema9.update(c.close);
    ema21.update(c.close);
    ema50.update(c.close);
    rsi.update(c.close);
    atr.update(c.high, c.low, c.close);
    candlesSeen++;

    final eq = p.equity(c.close);
    if (eq > peakEquity) peakEquity = eq;
    final dd = peakEquity - eq;
    if (dd > maxDrawdown) {
      maxDrawdown = dd;
      maxDrawdownPct = peakEquity > 0 ? dd / peakEquity * 100 : 0;
    }
    equityCurve.add(eq);

    final warm = candlesSeen >= warmupCandles;
    final crossUp = _prevEma9 <= _prevEma21 && ema9.value > ema21.value;
    final crossDown = _prevEma9 >= _prevEma21 && ema9.value < ema21.value;

    if (execute && warm) {
      if (!p.open) {
        // ENTRADA: cruzamento para cima + acima da EMA-50 + RSI confirma
        if (crossUp && c.close > ema50.value && rsi.value >= 52 && rsi.value <= 72) {
          final stopDist = atr.value * cfg.atrStopMult;
          if (stopDist > 0) {
            final equity = p.equity(c.close);
            var qty = (equity * cfg.riskPct) / stopDist;
            final maxQty = equity * (1 - StrategyConfig.feeRate) / c.close; // sem alavancagem
            qty = math.min(qty, maxQty);
            final px = c.close * (1 + StrategyConfig.slip);
            final cost = qty * px;
            final fee = cost * StrategyConfig.feeRate;
            if (qty > 0 && cost + fee <= p.cash) {
              p.cash -= cost + fee;
              p.qty = qty;
              p.entryPrice = px;
              p.entryTime = c.openTime;
              p.entryAtr = atr.value;
              p.open = true;
            }
          }
        }
      } else {
        // SAÍDA: stop → alvo → cruzamento inverso → sobrecompra
        final stopPx = p.entryPrice - p.entryAtr * cfg.atrStopMult;
        final tpPx = p.entryPrice + p.entryAtr * cfg.atrTpMult;
        double? exitPx;
        String? reason;
        if (c.low <= stopPx) {
          exitPx = stopPx;
          reason = 'Stop ATR (${cfg.atrStopMult.toStringAsFixed(1)}x)';
        } else if (c.high >= tpPx) {
          exitPx = tpPx;
          reason = 'Alvo ATR (+${cfg.atrTpMult.toStringAsFixed(1)}x)';
        } else if (crossDown) {
          exitPx = c.close;
          reason = 'Cruzamento EMA 9 abaixo da 21';
        } else if (rsi.value > 80) {
          exitPx = c.close;
          reason = 'RSI > 80 (esticado)';
        }
        if (exitPx != null) {
          _closePosition(c, exitPx, reason!);
        }
      }
    }

    _prevEma9 = ema9.value;
    _prevEma21 = ema21.value;
  }

  void _closePosition(Candle c, double rawExitPx, String reason) {
    final exitPx = rawExitPx * (1 - StrategyConfig.slip);
    final proceeds = p.qty * exitPx;
    final fee = proceeds * StrategyConfig.feeRate;
    p.cash += proceeds - fee;
    final cost = p.entryCost();
    final pnl = (proceeds - fee) - cost;
    final pnlPct = cost == 0 ? 0.0 : pnl / cost * 100;
    newTrades.add(Trade(
      entryTime: p.entryTime,
      exitTime: c.openTime,
      qty: p.qty,
      entryPrice: p.entryPrice,
      exitPrice: exitPx,
      pnl: pnl,
      pnlPct: pnlPct,
      reason: reason,
    ));
    p.qty = 0;
    p.open = false;
    p.entryPrice = 0;
    p.entryAtr = 0;
  }

  /// Fecha posição a mercado manualmente (botão "Fechar agora").
  Trade? closeMarket(Candle last, int nowMs) {
    if (!p.open) return null;
    _closePosition(last, last.close, 'Fechamento manual');
    return newTrades.isNotEmpty ? newTrades.last : null;
  }
}

/// -------------------------------------------------------------- backtest
class BacktestResult {
  final List<Trade> trades;
  final List<double> equityCurve;
  final double netPnl, roiPct, winRate, maxDrawdown, maxDrawdownPct, profitFactor, expectancy;
  final double buyAndHoldPct;
  final int wins, losses, totalTrades;
  final String sourceLabel;

  const BacktestResult({
    required this.trades,
    required this.equityCurve,
    required this.netPnl,
    required this.roiPct,
    required this.winRate,
    required this.maxDrawdown,
    required this.maxDrawdownPct,
    required this.profitFactor,
    required this.expectancy,
    required this.buyAndHoldPct,
    required this.wins,
    required this.losses,
    required this.totalTrades,
    required this.sourceLabel,
  });

  static BacktestResult compute(List<Candle> candles, StrategyConfig cfg, String sourceLabel) {
    final p = Portfolio();
    final s = Strategy(cfg, p);
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (int i = 0; i < candles.length; i++) {
      s.onCandle(candles[i], i, true, nowMs);
    }
    // Marca a mercado posição aberta no fim do período
    double equityFinal = p.cash;
    if (p.open && candles.isNotEmpty) {
      equityFinal += p.qty * candles.last.close * (1 - StrategyConfig.feeRate);
    }
    final netPnl = equityFinal - Portfolio.initialCash;

    final closed = s.newTrades;
    final wins = closed.where((t) => t.pnl > 0).length;
    final losses = closed.where((t) => t.pnl <= 0).length;
    final grossWin = closed.fold<double>(0, (a, t) => a + (t.pnl > 0 ? t.pnl : 0));
    final grossLoss = closed.fold<double>(0, (a, t) => a + (t.pnl < 0 ? -t.pnl : 0));
    final pf = grossLoss == 0 ? (grossWin > 0 ? 99.0 : 0.0) : grossWin / grossLoss;
    final wr = closed.isEmpty ? 0.0 : wins / closed.length * 100;
    final expectancy = closed.isEmpty ? 0.0 : netPnl / closed.length;
    final bh = candles.length > 1
        ? (candles.last.close - candles.first.open) / candles.first.open * 100
        : 0.0;

    return BacktestResult(
      trades: List.unmodifiable(closed),
      equityCurve: List.unmodifiable(s.equityCurve),
      netPnl: netPnl,
      roiPct: netPnl / Portfolio.initialCash * 100,
      winRate: wr,
      maxDrawdown: s.maxDrawdown,
      maxDrawdownPct: s.maxDrawdownPct,
      profitFactor: pf,
      expectancy: expectancy,
      buyAndHoldPct: bh,
      wins: wins,
      losses: losses,
      totalTrades: closed.length,
      sourceLabel: sourceLabel,
    );
  }
}
