// backtest.dart — Backtester offline/online: roda a estratégia balanceada nos
// últimos 90 dias (1h) e mostra winrate, P&L, drawdown máximo e curva de
// patrimônio. Dados: Binance 1h (cacheados) ou série sintética offline.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../engine.dart';
import '../fmt.dart';
import '../state.dart';
import '../theme.dart';

class BacktestScreen extends StatefulWidget {
  final AppController c;
  const BacktestScreen(this.c, {super.key});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  BacktestResult? _r;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await widget.c.runBacktest();
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return RefreshIndicator(
      color: kYellow,
      backgroundColor: kCardLight,
      onRefresh: _run,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          const SectionLabel('Backtest · últimos 90 dias · BTC/USDT 1h'),
          const SizedBox(height: 4),
          const Text(
            'Simulação da estratégia balanceada sobre os últimos 90 dias, com taxa de 0,1% e slippage. Começando com US\$ 100 e sem alavancagem.',
            style: TextStyle(color: kTextSoft, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_running && r == null)
            const CardBox(
              padding: EdgeInsets.all(28),
              child: Column(
                children: [
                  CircularProgressIndicator(color: kYellow, strokeWidth: 2.4),
                  SizedBox(height: 12),
                  Text('Rodando a estratégia em ~2.160 velas de 1h…',
                      style: TextStyle(color: kTextSoft, fontSize: 12)),
                ],
              ),
            )
          else if (_error != null && r == null)
            CardBox(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, color: kRed, size: 30),
                  const SizedBox(height: 8),
                  Text('Falha no backtest: $_error',
                      style: const TextStyle(color: kTextSoft, fontSize: 12)),
                  const SizedBox(height: 10),
                  FilledButton(
                      onPressed: _run, child: const Text('Tentar de novo')),
                ],
              ),
            )
          else if (r != null) ...[
            InfoChip(r.sourceLabel, color: kYellow),
            const SizedBox(height: 12),
            // Resultado principal
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Resultado no período (US\$ 100 →)'),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fmtUsd(100 + r.netPnl),
                        style: const TextStyle(
                            color: kText,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          '${fmtUsd(r.netPnl, sign: true)} (${fmtPct(r.roiPct)})',
                          style: TextStyle(
                              color: r.netPnl >= 0 ? kGreen : kRed,
                              fontSize: 15,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: CustomPaint(
                        painter: _EquityCurvePainter(r.equityCurve),
                        child: const SizedBox.expand()),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    r.buyAndHoldPct >= 0
                        ? 'Comparar: comprar e segurar BTC teria dado ${fmtPct(r.buyAndHoldPct)} no mesmo período.'
                        : 'Comparar: comprar e segurar BTC teria dado ${fmtPct(r.buyAndHoldPct)} no mesmo período.',
                    style: const TextStyle(color: kTextSoft, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Grade de métricas
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Métricas'),
                  const SizedBox(height: 12),
                  _metricRow('Winrate', r.totalTrades == 0
                      ? '—'
                      : '${r.winRate.toStringAsFixed(1)}%  (${r.wins}V / ${r.losses}D)'),
                  _metricRow('Trades fechados', '${r.totalTrades}'),
                  _metricRow('Profit factor', r.profitFactor >= 99
                      ? '∞ (sem perdas)'
                      : r.profitFactor.toStringAsFixed(2)),
                  _metricRow('Expectância / trade', fmtUsd(r.expectancy, sign: true)),
                  _metricRow('Drawdown máximo',
                      '${fmtUsd(-r.maxDrawdown)}  (${r.maxDrawdownPct.toStringAsFixed(1)}% do pico)',
                      valueColor: kRed),
                  _metricRow('ROI total', fmtPct(r.roiPct),
                      valueColor: r.roiPct >= 0 ? kGreen : kRed),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Últimas operações do backtest
            if (r.trades.isNotEmpty)
              CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Últimas operações simuladas'),
                    const SizedBox(height: 8),
                    ...r.trades.reversed.take(6).map((t) {
                      final win = t.pnl >= 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Icon(win ? Icons.check_circle : Icons.cancel,
                                size: 15, color: win ? kGreen : kRed),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(t.reason,
                                  style: const TextStyle(
                                      color: kText, fontSize: 11, height: 1.3)),
                            ),
                            Text(fmtUsd(t.pnl, sign: true),
                                style: TextStyle(
                                    color: win ? kGreen : kRed,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ])),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kYellow,
                  side: const BorderSide(color: kYellow),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: kYellow, strokeWidth: 2))
                    : const Icon(Icons.replay, size: 18),
                label: const Text('RODAR DE NOVO',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Backtest usa velas de 1h; a operação ao vivo usa velas de 5m, então os resultados diferem um pouco. '
              'Resultados passados (ou sintéticos) não garantem resultados futuros.',
              style: TextStyle(color: kTextSoft, fontSize: 10, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, {Color valueColor = kText}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: kTextSoft, fontSize: 12)),
            ),
            Text(value,
                style: TextStyle(
                    color: valueColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      );
}

class _EquityCurvePainter extends CustomPainter {
  final List<double> curve;
  _EquityCurvePainter(this.curve);

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.length < 2) return;
    // Amostra a curva para o desenho
    final step = math.max(1, curve.length ~/ 240);
    final pts = <Offset>[];
    double minV = curve.reduce(math.min), maxV = curve.reduce(math.max);
    if ((maxV - minV).abs() < 1e-9) {
      maxV = minV + 1;
    }
    final pad = (maxV - minV) * 0.1;
    minV -= pad;
    maxV += pad;
    for (int i = 0; i < curve.length; i += step) {
      final x = i / (curve.length - 1) * size.width;
      final y = size.height - (curve[i] - minV) / (maxV - minV) * size.height;
      pts.add(Offset(x, y));
    }
    pts.add(Offset(size.width, size.height - (curve.last - minV) / (maxV - minV) * size.height));

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    // Área preenchida
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = kYellow.withValues(alpha: 0.12)..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = kYellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    // Linha do capital inicial (100)
    final y100 = size.height - (100 - minV) / (maxV - minV) * size.height;
    if (y100 >= 0 && y100 <= size.height) {
      final p = Paint()
        ..color = kTextSoft.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y100), Offset(x + 6, y100), p);
        x += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EquityCurvePainter oldDelegate) =>
      !identical(oldDelegate.curve, curve);
}
