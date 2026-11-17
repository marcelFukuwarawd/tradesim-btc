// main.dart — TradeSim BTC: ponto de entrada.
// Simulador de trade automático BTC/USDT (paper trading), 100% local para a
// conta + preços reais públicos da Binance. Sem login, sem chave de API.
import 'package:material_ui/material_ui.dart';

import 'screens/backtest.dart';
import 'screens/history.dart';
import 'screens/home.dart';
import 'screens/settings.dart';
import 'state.dart';
import 'theme.dart';

final AppController appController = AppController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // O init pesado (DB + 1ª coleta) acontece em background; a UI aparece rápido.
  appController.init();
  runApp(const TradeSimApp());
}

class TradeSimApp extends StatelessWidget {
  const TradeSimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TradeSim BTC',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            HomeScreen(appController),
            BacktestScreen(appController),
            HistoryScreen(appController),
            SettingsScreen(appController),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: kCard,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.candlestick_chart_outlined),
            selectedIcon: Icon(Icons.candlestick_chart),
            label: 'Trade',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Backtest',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Relatórios',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
