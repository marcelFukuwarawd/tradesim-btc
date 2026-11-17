// home.dart — Tela "Trade": gráfico de candles (estilo Binance/TradingView),
// painel da conta (US$ 100 iniciais, sem alavancagem) e posição aberta.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../engine.dart';
import '../fmt.dart';
import '../state.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  final AppController c;
  const HomeScreen(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final t = c.ticker;
        final chg = t?.priceChangePercent ?? 0;
        final up = chg >= 0;
        return RefreshIndicator(
          color: kYellow,
          backgroundColor: kCardLight,
          onRefresh: () => c.refresh(forceBootstrap: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 26),
            children: [
              _topBar(c),
              const SizedBox(height: 10),
              _priceBlock(c, t, chg, up),
              const SizedBox(height: 10),
              _chartCard(c),
              if (c.inPosition) ...[
                const SizedBox(height: 10),
                _positionBanner(context, c),
              ],
              if (c.mode == FeedMode.offline) ...[
                const SizedBox(height: 10),
                _offlineBanner(),
              ],
              const SizedBox(height: 12),
              _accountPanel(c),
              const SizedBox(height: 10),
              _autoTradeRow(c),
              const SizedBox(height: 14),
              const Text(
                'Simulação (paper trading) com preços públicos reais da Binance.\n'
                'Não é conselho financeiro. Resultados passados não garantem lucros.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextSoft, fontSize: 10.5, height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------- topo
  Widget _topBar(AppController c) => Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kYellow,
              borderRadius: BorderRadius.circular(11),
              boxShadow: const [
                BoxShadow(color: Color(0x55F0B90B), blurRadius: 14, offset: Offset(0, 3)),
              ],
            ),
            alignment: Alignment.center,
            child: const Text('₿',
                style: TextStyle(
                    color: Color(0xFF1E2329),
                    fontSize: 22,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TradeSim BTC',
                  style: TextStyle(
                      color: kText,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2)),
              Text('Trade automático · BTC/USDT',
                  style: TextStyle(color: kTextSoft, fontSize: 10.5)),
            ],
          ),
          const Spacer(),
          _feedChip(c),
        ],
      );

  Widget _feedChip(AppController c) {
    switch (c.mode) {
      case FeedMode.live:
        return const InfoChip('AO VIVO', color: kGreen);
      case FeedMode.offline:
        return const InfoChip('OFFLINE', color: kYellow);
      case FeedMode.connecting:
        return const InfoChip('CONECTANDO…', color: kTextSoft);
    }
  }

  // ------------------------------------------------- bloco de preço
  Widget _priceBlock(AppController c, Ticker24h? t, double chg, bool up) {
    final color = up ? kGreen : kRed;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('BTC/USDT',
                      style: TextStyle(
                          color: kText,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                  const SizedBox(width: 8),
                  const InfoChip('SIMULADO', color: kYellow),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                t == null ? '—' : fmtUsd(c.lastPrice),
                style: const TextStyle(
                  color: kText,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: color, size: 20),
                  Text(fmtPct(chg),
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                  const Text('  24h', style: TextStyle(color: kTextSoft, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        // Stats 24h à direita
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _miniStat('MÁX 24H', t == null ? '—' : fmtUsd(t.high)),
            const SizedBox(height: 4),
            _miniStat('MÍN 24H', t == null ? '—' : fmtUsd(t.low)),
            const SizedBox(height: 4),
            _miniStat('VOL 24H',
                t == null ? '—' : fmtCompactUsd(t.quoteVolume)),
          ],
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: const TextStyle(
                  color: kTextSoft, fontSize: 9, fontWeight: FontWeight.w700)),
          Text(value,
              style: const TextStyle(
                  color: kText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ],
      );

  // ------------------------------------------------------ gráfico
  Widget _chartCard(AppController c) => CardBox(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SectionLabel('BTC/USDT · 5m'),
                const Spacer(),
                _legendDot(kYellow, 'EMA 9'),
                const SizedBox(width: 10),
                _legendDot(kPurple, 'EMA 21'),
                const SizedBox(width: 10),
                _legendDot(kGreen, 'Candles'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 235,
              width: double.infinity,
              child: CustomPaint(
                painter: CandleChartPainter(c.candles5m),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      );

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, borderRadius: BorderRadius.circular(99))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: kTextSoft, fontSize: 10)),
        ],
      );

  // -------------------------------------------- banner de posição
  Widget _positionBanner(BuildContext context, AppController c) {
    final stop = c.portfolio.entryPrice - c.portfolio.entryAtr * c.atrStopMult;
    final target = c.portfolio.entryPrice + c.portfolio.entryAtr * c.atrTpMult;
    final unreal = c.unrealizedPnl;
    final color = unreal >= 0 ? kGreen : kRed;
    return CardBox(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: kYellow, size: 16),
              const SizedBox(width: 6),
              const Text('POSIÇÃO COMPRADA',
                  style: TextStyle(
                      color: kYellow,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1)),
              const Spacer(),
              Text(fmtUsd(unreal, sign: true),
                  style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${fmtBtc(c.portfolio.qty)} BTC  @  ${fmtUsd(c.portfolio.entryPrice)}',
            style: const TextStyle(
                color: kText,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 2),
          Text(
            'Alvo ${fmtUsd(target)}   ·   Stop ${fmtUsd(stop)}   ·   P&L não realizado',
            style: const TextStyle(color: kTextSoft, fontSize: 10.5),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: kRed,
                side: const BorderSide(color: kRed, width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _confirmClose(context, c),
              child: const Text('FECHAR POSIÇÃO AGORA',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 11.5)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(BuildContext context, AppController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardLight,
        title: const Text('Fechar posição?', style: TextStyle(color: kText)),
        content: const Text(
          'Vende todo o BTC da posição a preço de mercado (com taxa de 0,1%). '
          'Esta ação é só na simulação.',
          style: TextStyle(color: kTextSoft),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: kTextSoft))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final t = await c.closePosition();
      if (context.mounted && t != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Posição fechada · P&L ${fmtUsd(t.pnl, sign: true)} (${fmtPct(t.pnlPct)})'),
        ));
      }
    }
  }

  Widget _offlineBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kYellow.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kYellow.withValues(alpha: 0.45)),
        ),
        child: const Row(
          children: [
            Icon(Icons.cloud_off, color: kYellow, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Offline — o gráfico mostra dados sintéticos e os trades automáticos ficam pausados até a rede voltar.',
                style: TextStyle(color: kYellow, fontSize: 11.5, height: 1.35),
              ),
            ),
          ],
        ),
      );

  // ------------------------------------------- painel da conta
  Widget _accountPanel(AppController c) => CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Conta · US\$ 100 iniciais · sem alavancagem'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: StatTile(label: 'Caixa', value: fmtUsd(c.portfolio.cash))),
                Expanded(
                    child: StatTile(label: 'Patrimônio', value: fmtUsd(c.equity))),
                Expanded(
                  child: StatTile(
                    label: 'ROI total',
                    value: fmtPct(c.roiPct),
                    valueColor: c.roiPct >= 0 ? kGreen : kRed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'P&L hoje',
                    value: fmtUsd(c.todayPnl, sign: true),
                    valueColor: c.todayPnl >= 0 ? kGreen : kRed,
                    sub:
                        '${c.todayTradeCount} ${c.todayTradeCount == 1 ? 'trade' : 'trades'} · ${c.todayWins}V',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Winrate',
                    value: c.totalTrades == 0
                        ? '—'
                        : '${(c.totalWins / c.totalTrades * 100).toStringAsFixed(0)}%',
                    sub: '${c.totalWins}V / ${c.totalTrades - c.totalWins}D',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Posição',
                    value: c.inPosition ? 'Comprado' : 'Zerado',
                    valueColor: c.inPosition ? kYellow : kTextSoft,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _autoTradeRow(AppController c) => CardBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.smart_toy_outlined, color: kYellow, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Operação automática',
                      style: TextStyle(
                          color: kText, fontSize: 13.5, fontWeight: FontWeight.w800)),
                  Text('Estratégia balanceada · risco ≤ 2% por trade · 0,1% de taxa',
                      style: TextStyle(color: kTextSoft, fontSize: 10.5)),
                ],
              ),
            ),
            Switch(
              value: c.autoTrade,
              activeThumbColor: kYellow,
              activeTrackColor: kYellow.withValues(alpha: 0.35),
              onChanged: c.setAutoTrade,
            ),
          ],
        ),
      );
}

/// -------------------------------------------------- gráfico de candles
class CandleChartPainter extends CustomPainter {
  final List<Candle> data;
  CandleChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final axisW = 54.0;
    final topPad = 6.0;
    final volHeight = size.height * 0.17;
    final chartH = size.height - volHeight - topPad;
    final plotW = size.width - axisW;

    if (data.length < 5) {
      final tp = TextPainter(
        text: const TextSpan(
            text: 'Sem dados — puxe para atualizar',
            style: TextStyle(color: kTextSoft, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((plotW - tp.width) / 2, size.height / 2));
      return;
    }

    // EMAs sobre a janela visível (aproximação local)
    double ema(double prev, double x, int period) {
      final k = 2.0 / (period + 1);
      return x * k + prev * (1 - k);
    }

    final e9 = <double>[];
    final e21 = <double>[];
    double a9 = data.first.close, a21 = data.first.close;
    for (final c in data) {
      a9 = ema(a9, c.close, 9);
      a21 = ema(a21, c.close, 21);
      e9.add(a9);
      e21.add(a21);
    }

    double minP = data.map((e) => e.low).reduce(math.min);
    double maxP = data.map((e) => e.high).reduce(math.max);
    minP = math.min(minP, e9.reduce(math.min));
    minP = math.min(minP, e21.reduce(math.min));
    maxP = math.max(maxP, e9.reduce(math.max));
    maxP = math.max(maxP, e21.reduce(math.max));
    final pad = (maxP - minP) * 0.06 + 1e-9;
    minP -= pad;
    maxP += pad;

    final maxVol = data.map((e) => e.volume).reduce(math.max);
    double yFor(double p) => topPad + (maxP - p) / (maxP - minP) * chartH;
    final n = data.length;
    final step = plotW / n;
    final bodyW = math.max(2.0, step * 0.6);

    final gridPaint = Paint()
      ..color = kBorder.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final textStyle = const TextStyle(color: kTextSoft, fontSize: 9);

    // Grade horizontal + rótulos de preço (4 linhas)
    for (int i = 0; i <= 3; i++) {
      final y = topPad + chartH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(plotW, y), gridPaint);
      final price = maxP - (maxP - minP) * i / 3;
      final tp = TextPainter(
        text: TextSpan(text: _compactPrice(price), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: axisW);
      tp.paint(canvas, Offset(plotW + 6, y - tp.height / 2));
    }

    // Barras de volume (parte inferior)
    final volTop = topPad + chartH + 4;
    for (int i = 0; i < n; i++) {
      final c = data[i];
      final h = maxVol == 0 ? 0.0 : c.volume / maxVol * (volHeight - 6);
      final x = i * step + (step - bodyW) / 2;
      final up = c.close >= c.open;
      canvas.drawRect(
        Rect.fromLTWH(x, volTop + (volHeight - 6) - h, bodyW, h),
        Paint()..color = (up ? kGreen : kRed).withValues(alpha: 0.35),
      );
    }

    // Candles
    final wickPaint = Paint()..strokeWidth = 1;
    for (int i = 0; i < n; i++) {
      final c = data[i];
      final up = c.close >= c.open;
      final color = up ? kGreen : kRed;
      final cx = i * step + step / 2;
      wickPaint.color = color;
      canvas.drawLine(Offset(cx, yFor(c.high)), Offset(cx, yFor(c.low)), wickPaint);
      final yOpen = yFor(c.open);
      final yClose = yFor(c.close);
      final top = math.min(yOpen, yClose);
      final height = math.max(1.0, (yOpen - yClose).abs());
      canvas.drawRect(
        Rect.fromLTWH(cx - bodyW / 2, top, bodyW, height),
        Paint()..color = color,
      );
    }

    // Linhas EMA
    void polyline(List<double> series, Color color) {
      final path = Path();
      for (int i = 0; i < series.length; i++) {
        final x = i * step + step / 2;
        final y = yFor(series[i]);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }

    polyline(e9, kYellow);
    polyline(e21, kPurple);

    // Linha tracejada do preço atual + etiqueta
    final lastY = yFor(data.last.close).clamp(topPad, topPad + chartH).toDouble();
    final dashPaint = Paint()
      ..color = kYellow.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    double x = 0;
    while (x < plotW) {
      canvas.drawLine(Offset(x, lastY), Offset(x + 5, lastY), dashPaint);
      x += 9;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: _compactPrice(data.last.close),
        style: const TextStyle(
            color: Color(0xFF1E2329), fontSize: 9, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final tagRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(plotW + 2, lastY - tp.height / 2 - 3, axisW - 4, tp.height + 6),
      const Radius.circular(4),
    );
    canvas.drawRRect(tagRect, Paint()..color = kYellow);
    tp.paint(canvas, Offset(plotW + 2 + (axisW - 4 - tp.width) / 2, lastY - tp.height / 2));
  }

  String _compactPrice(double p) =>
      p >= 1000 ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

  @override
  bool shouldRepaint(covariant CandleChartPainter oldDelegate) => true;
}
