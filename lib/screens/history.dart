// history.dart — Relatórios diários (09h→21h, gerados às 21h) e histórico de
// operações fechadas. Tudo salvo localmente no SQLite.
import 'package:material_ui/material_ui.dart';

import '../db.dart';
import '../engine.dart';
import '../fmt.dart';
import '../state.dart';
import '../theme.dart';

class HistoryScreen extends StatefulWidget {
  final AppController c;
  const HistoryScreen(this.c, {super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<ReportRow> _reports = [];
  List<Trade> _trades = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    widget.c.addListener(_reload);
    _reload();
  }

  Future<void> _reload() async {
    final reports = await Db.I.allReports();
    final trades = await Db.I.allTrades(limit: 300);
    if (mounted) {
      setState(() {
        _reports = reports;
        _trades = trades;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    widget.c.removeListener(_reload);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _generateToday() async {
    final row = await widget.c.generateDailyReport(DateTime.now());
    await Db.I.putMeta('last_report_date', row.date);
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Relatório de ${row.date} salvo: '
            '${fmtUsd(row.realizedPnl, sign: true)} (${fmtPct(row.roiPct)})'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Row(
            children: [
              const Expanded(child: SectionLabel('Relatórios & Operações')),
              TextButton.icon(
                onPressed: _generateToday,
                icon: const Icon(Icons.playlist_add_check, size: 17, color: kYellow),
                label: const Text('Gerar hoje',
                    style: TextStyle(
                        color: kYellow, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          indicatorColor: kYellow,
          labelColor: kYellow,
          unselectedLabelColor: kTextSoft,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          tabs: const [
            Tab(text: 'Relatórios diários'),
            Tab(text: 'Operações'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kYellow))
              : TabBarView(
                  controller: _tabs,
                  children: [_reportsTab(), _tradesTab()],
                ),
        ),
      ],
    );
  }

  Widget _reportsTab() {
    if (_reports.isEmpty) {
      return _emptyState(
        Icons.receipt_long_outlined,
        'Nenhum relatório ainda',
        'O relatório das 21h é gerado automaticamente todo dia. '
        'Você também pode tocar em "Gerar hoje" acima.',
      );
    }
    final totalPnl = _reports.fold<double>(0, (a, r) => a + r.realizedPnl);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
      children: [
        CardBox(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Resultado acumulado',
                  value: fmtUsd(totalPnl, sign: true),
                  valueColor: totalPnl >= 0 ? kGreen : kRed,
                  sub: '${_reports.length} ${_reports.length == 1 ? 'dia' : 'dias'} com relatório',
                ),
              ),
              const Icon(Icons.insights, color: kYellow, size: 30),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ..._reports.map(_reportCard),
      ],
    );
  }

  Widget _reportCard(ReportRow r) {
    final pnlColor = r.realizedPnl >= 0 ? kGreen : kRed;
    final date = DateTime.tryParse(r.date);
    final title = date != null ? fmtDateShort(date) : r.date;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: pnlColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                r.realizedPnl >= 0 ? Icons.trending_up : Icons.trending_down,
                color: pnlColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: kText, fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${r.trades} ${r.trades == 1 ? 'trade' : 'trades'} · ${r.wins}V/${r.losses}D · caixa ${fmtUsd(r.endCash)}',
                    style: const TextStyle(color: kTextSoft, fontSize: 11),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fmtUsd(r.realizedPnl, sign: true),
                    style: TextStyle(
                        color: pnlColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                Text(fmtPct(r.roiPct),
                    style: TextStyle(
                        color: pnlColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tradesTab() {
    if (_trades.isEmpty) {
      return _emptyState(
        Icons.candlestick_chart_outlined,
        'Nenhuma operação fechada ainda',
        'Quando a estratégia detectar um cruzamento válido, a compra/venda simulada aparecerá aqui com o P&L detalhado.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
      itemCount: _trades.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final t = _trades[i];
        final win = t.pnl >= 0;
        final exit = DateTime.fromMillisecondsSinceEpoch(t.exitTime).toLocal();
        return CardBox(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('BUY',
                    style: TextStyle(
                        color: kGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmtDateTimeShort(exit),
                        style: const TextStyle(
                            color: kText,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                    Text(t.reason,
                        style: const TextStyle(
                            color: kTextSoft, fontSize: 10, height: 1.3)),
                    const SizedBox(height: 2),
                    Text(
                        '${fmtBtc(t.qty)} BTC · entrada ${fmtUsd(t.entryPrice)} · saída ${fmtUsd(t.exitPrice)}',
                        style: const TextStyle(
                            color: kTextSoft, fontSize: 10,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmtUsd(t.pnl, sign: true),
                      style: TextStyle(
                          color: win ? kGreen : kRed,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  Text(fmtPct(t.pnlPct),
                      style: TextStyle(
                          color: win ? kGreen : kRed,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyState(IconData icon, String title, String sub) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: kBorder, size: 52),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: kTextSoft, fontSize: 11.5, height: 1.45)),
            ],
          ),
        ),
      );
}
