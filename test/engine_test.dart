// Testes do motor: determinismo do mercado sintético, indicadores e backtest.
import 'package:flutter_test/flutter_test.dart';

import 'package:btc_trader_sim/engine.dart';

void main() {
  test('RNG Mulberry32 é determinístico', () {
    final a = Mulberry32(123);
    final b = Mulberry32(123);
    for (int i = 0; i < 100; i++) {
      expect(a.next(), b.next());
    }
  });

  test('mercado sintético é determinístico e avança no tempo', () {
    final m1 = SyntheticMarket.genesis();
    final m2 = SyntheticMarket.genesis();
    for (int i = 0; i < 50; i++) {
      final c1 = m1.nextCandle();
      final c2 = m2.nextCandle();
      expect(c1.openTime, c2.openTime);
      expect(c1.close, c2.close);
      expect(c1.open, lessThanOrEqualTo(c1.high));
      expect(c1.close, lessThanOrEqualTo(c1.high));
      expect(c1.open, greaterThanOrEqualTo(c1.low));
      expect(c1.close, greaterThanOrEqualTo(c1.low));
    }
  });

  test('EMA segue o preço e fica finita', () {
    final e = Ema(9);
    double v = 0;
    for (int i = 0; i < 100; i++) {
      v = e.update(100 + i * 0.1);
    }
    expect(v.isFinite, isTrue);
    expect(v, greaterThan(100));
  });

  test('RSI permanece entre 0 e 100', () {
    final r = Rsi(14);
    for (int i = 0; i < 200; i++) {
      r.update(100 + 10 * (i % 7 == 0 ? -1 : 1) * (i % 3 + 1));
      expect(r.value, inInclusiveRange(0, 100));
    }
  });

  test('backtest sintético 90 dias retorna métricas finitas e sem alavancagem', () {
    final series = SyntheticMarket.lastDays(90);
    final hourly = resample(series, 12); // 5m -> 1h
    final r = BacktestResult.compute(hourly, StrategyConfig(), 'teste');
    expect(r.equityCurve.isNotEmpty, isTrue);
    expect(r.netPnl.isFinite, isTrue);
    expect(r.roiPct.isFinite, isTrue);
    expect(r.winRate, inInclusiveRange(0, 100));
    expect(r.profitFactor.isFinite, isTrue);
    expect(r.profitFactor, greaterThanOrEqualTo(0));
    expect(r.maxDrawdown, greaterThanOrEqualTo(0));
    expect(r.totalTrades, r.wins + r.losses);
  });

  test('backtest é reproduzível (mesmo resultado duas vezes)', () {
    final series = SyntheticMarket.lastDays(30);
    final hourly = resample(series, 12);
    final r1 = BacktestResult.compute(hourly, StrategyConfig(), 'a');
    final r2 = BacktestResult.compute(hourly, StrategyConfig(), 'b');
    expect(r1.netPnl, r2.netPnl);
    expect(r1.totalTrades, r2.totalTrades);
    expect(r1.equityCurve.last, r2.equityCurve.last);
  });

  test('posição respeita caixa disponível (sem alavancagem)', () {
    final p = Portfolio();
    final cfg = StrategyConfig(riskPct: 0.02);
    final s = Strategy(cfg, p);
    final series = SyntheticMarket.lastDays(60);
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    double minCashSeen = double.infinity;
    for (int i = 0; i < series.length; i++) {
      s.onCandle(series[i], i, true, nowMs);
      if (p.cash < minCashSeen) minCashSeen = p.cash;
    }
    expect(minCashSeen, greaterThanOrEqualTo(-0.000001));
  });
}
