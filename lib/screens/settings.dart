// settings.dart — Ajustes: risco por operação, stop/alvo (×ATR), notificação
// das 21h, zerar a simulação e a explicação da estratégia.
import 'package:material_ui/material_ui.dart';

import '../notifications.dart';
import '../state.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  final AppController c;
  const SettingsScreen(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          const SectionLabel('Ajustes da estratégia'),
          const SizedBox(height: 10),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sliderRow(
                  label: 'Risco por operação',
                  value: '${(c.riskPct * 100).toStringAsFixed(1)}% do patrimônio',
                  min: 0.005,
                  max: 0.05,
                  divisions: 9,
                  current: c.riskPct,
                  onChanged: c.setRiskPct,
                  hint: 'Van Tharp / Schwager: nunca arrisque mais que 1–2% por trade.',
                ),
                const Divider(height: 22, color: kBorder),
                _sliderRow(
                  label: 'Stop (×ATR-14)',
                  value: '${c.atrStopMult.toStringAsFixed(1)} × ATR',
                  min: 1.0,
                  max: 3.0,
                  divisions: 20,
                  current: c.atrStopMult,
                  onChanged: c.setAtrStopMult,
                  hint: 'Wilder (ATR): saída protetora sob a mínima do movimento.',
                ),
                const Divider(height: 22, color: kBorder),
                _sliderRow(
                  label: 'Alvo (×ATR-14)',
                  value: '${c.atrTpMult.toStringAsFixed(1)} × ATR',
                  min: 1.5,
                  max: 5.0,
                  divisions: 35,
                  current: c.atrTpMult,
                  onChanged: c.setAtrTpMult,
                  hint: 'Com stop 1.8 e alvo 3.0, ganho médio ≈ 1.67× a perda média.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SectionLabel('Relatório das 21h'),
          const SizedBox(height: 10),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Notificação local diária às 21:00 (America/Sao_Paulo) com ganhos/perdas do dia. Não usa internet nem Firebase.',
                    style: TextStyle(color: kTextSoft, fontSize: 11.5, height: 1.45)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kYellow,
                          side: const BorderSide(color: kYellow),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          await NotificationService.requestPermission();
                          final body = await c.pendingNotificationBody();
                          await NotificationService.showNow(
                              'TradeSim BTC — Teste de notificação', body);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('Notificação de teste enviada.')));
                          }
                        },
                        icon: const Icon(Icons.notifications_active, size: 18),
                        label: const Text('Testar',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kText,
                          side: const BorderSide(color: kBorder),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          await c.refresh();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('Relatório das 21h reagendado com os números atuais.')));
                          }
                        },
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('Reagendar',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Dica: se o celular "matar" apps em segundo plano, abra o TradeSim BTC '
                  'pelo menos uma vez no dia para o relatório vir com os números do momento — '
                  'o horário das 21h é garantido pelo Android.',
                  style: TextStyle(color: kTextSoft, fontSize: 10, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SectionLabel('A estratégia balanceada'),
          const SizedBox(height: 10),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _rule('1', 'Tendência (John J. Murphy)',
                    'Compra somente quando a EMA-9 cruza ACIMA da EMA-21 e o preço está acima da EMA-50. Nunca contra a tendência.'),
                _rule('2', 'Momento (J. Welles Wilder)',
                    'RSI-14 entre 52 e 72 na entrada (força sem exagero). Sai se o RSI passar de 80 (esticado).'),
                _rule('3', 'Risco e dimensionamento (Van Tharp, Schwager)',
                    'Arrisca no máximo 2% do patrimônio por operação. Posição limitada pelo caixa — spot, SEM alavancagem. 100% do trade diário a partir de US\$ 100.'),
                _rule('4', 'Stop e alvo (Wilder — ATR)',
                    'Stop = 1,8×ATR-14 abaixo da entrada · Alvo = 3,0×ATR-14 acima. Sai também no cruzamento inverso EMA-9/EMA-21.'),
                _rule('5', 'Custos reais (Binance)',
                    'Taxa de 0,1% (taker) por lado + 0,05% de slippage ao entrar e sair. Composto: os lucros aumentam a base dos trades seguintes.'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SectionLabel('Zona de risco'),
          const SizedBox(height: 10),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Apaga a conta, os trades e os relatórios e recomeça com US\$ 100.',
                    style: TextStyle(color: kTextSoft, fontSize: 11.5)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kRed,
                      side: const BorderSide(color: kRed),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _confirmReset(context, c),
                    icon: const Icon(Icons.delete_forever, size: 18),
                    label: const Text('ZERAR SIMULAÇÃO (US\$ 100)',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            fontSize: 11.5)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'TradeSim BTC v1.0.0\n'
            'Preços: API pública da Binance (sem login, sem chave, sem ordens reais).\n'
            'Trades: 100% simulados. Este app não é conselho financeiro.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextSoft, fontSize: 10.5, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required String value,
    required double min,
    required double max,
    required int divisions,
    required double current,
    required ValueChanged<double> onChanged,
    required String hint,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: kText, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              Text(value,
                  style: const TextStyle(
                      color: kYellow, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          Slider(
            value: current.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: kYellow,
            inactiveColor: kBorder,
            onChanged: onChanged,
          ),
          Text(hint,
              style: const TextStyle(color: kTextSoft, fontSize: 10, height: 1.35)),
        ],
      );

  Widget _rule(String n, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                  color: kYellow, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(n,
                  style: const TextStyle(
                      color: Color(0xFF1E2329),
                      fontSize: 11,
                      fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: kText, fontSize: 11.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          color: kTextSoft, fontSize: 10.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );

  Future<void> _confirmReset(BuildContext context, AppController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardLight,
        title: const Text('Zerar simulação?', style: TextStyle(color: kText)),
        content: const Text(
          'Apaga saldo, posição, histórico de trades e relatórios. Recomeça com US\$ 100. Não afeta nada fora do app.',
          style: TextStyle(color: kTextSoft),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: kTextSoft))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Zerar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await c.resetSimulation();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Simulação zerada. Conta com US\$ 100.')));
      }
    }
  }
}
