// api.dart — Cliente da API PÚBLICA da Binance (dados de mercado somente).
//
// NÃO usa login, NÃO usa chave de API, NÃO executa ordens. Apenas leitura de
// preços e candles públicos de BTC/USDT (mesmos dados que aparecem em
// binance.com). Se todas as bases falharem (sem rede), o app cai no modo
// offline com candles sintéticos e pausa os trades automáticos.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'engine.dart';

class Ticker24h {
  final double last, priceChangePercent, high, low, quoteVolume;
  const Ticker24h({
    required this.last,
    required this.priceChangePercent,
    required this.high,
    required this.low,
    required this.quoteVolume,
  });
}

class BinanceException implements Exception {
  final String message;
  BinanceException(this.message);
  @override
  String toString() => 'BinanceException: $message';
}

class BinanceClient {
  // data-api.binance.vision é o domínio oficial de dados públicos (sem geo-block
  // na maior parte do mundo). api.binance.com / api1-api4 são espelhos.
  static const List<String> _bases = [
    'https://data-api.binance.vision',
    'https://api.binance.com',
    'https://api1.binance.com',
    'https://api2.binance.com',
    'https://api3.binance.com',
    'https://api4.binance.com',
  ];

  final http.Client _http = http.Client();

  Future<dynamic> _getJson(String pathWithQuery) async {
    Object? lastError;
    for (final base in _bases) {
      try {
        final r = await _http
            .get(Uri.parse('$base$pathWithQuery'), headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 12));
        if (r.statusCode == 200) {
          return jsonDecode(r.body);
        }
        lastError = BinanceException('HTTP ${r.statusCode} em $base');
      } catch (e) {
        lastError = e;
      }
    }
    throw BinanceException('Todas as bases da Binance falharam. ${lastError ?? ''}');
  }

  /// Últimas [limit] velas de [interval] (ex.: "5m"). Se [endTime] for passado,
  /// traz as velas mais recentes ATÉ esse instante.
  Future<List<Candle>> klines({String interval = '5m', int limit = 160, int? endTime}) async {
    final q = '/api/v3/klines?symbol=BTCUSDT&interval=$interval&limit=$limit'
        '${endTime != null ? '&endTime=$endTime' : ''}';
    final data = await _getJson(q) as List<dynamic>;
    return data.map((e) => Candle.fromBinanceK(e as List<dynamic>)).toList();
  }

  /// Todas as velas desde [startTime] até agora, em páginas de 1000 para a frente.
  Future<List<Candle>> klinesSince({String interval = '5m', required int startTime}) async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final out = <Candle>[];
    var cursor = startTime;
    final step = _intervalMs(interval);
    for (int page = 0; page < 80; page++) {
      final window = await _klinesWindow(interval: interval, startTime: cursor, limit: 1000);
      if (window.isEmpty) break;
      out.addAll(window);
      final next = window.last.openTime + step;
      if (next <= cursor) break; // segurança anti-loop
      cursor = next;
      if (window.length < 1000 || cursor > nowMs) break;
    }
    return out;
  }

  Future<List<Candle>> _klinesWindow(
      {required String interval, required int startTime, int limit = 1000}) async {
    final q =
        '/api/v3/klines?symbol=BTCUSDT&interval=$interval&startTime=$startTime&limit=$limit';
    final data = await _getJson(q) as List<dynamic>;
    return data.map((e) => Candle.fromBinanceK(e as List<dynamic>)).toList();
  }

  static int _intervalMs(String interval) {
    final unit = interval.substring(interval.length - 1);
    final n = int.parse(interval.substring(0, interval.length - 1));
    switch (unit) {
      case 'm':
        return n * 60 * 1000;
      case 'h':
        return n * 3600 * 1000;
      case 'd':
        return n * 86400 * 1000;
      case 'w':
        return n * 7 * 86400 * 1000;
      default:
        return n * 60 * 1000;
    }
  }

  /// Estatísticas das últimas 24h (preço atual, variação, máxima, mínima, volume).
  Future<Ticker24h> ticker24h() async {
    final data = await _getJson('/api/v3/ticker/24hr?symbol=BTCUSDT') as Map<String, dynamic>;
    double d(String k) => double.tryParse(data[k]?.toString() ?? '0') ?? 0;
    return Ticker24h(
      last: d('lastPrice'),
      priceChangePercent: d('priceChangePercent'),
      high: d('highPrice'),
      low: d('lowPrice'),
      quoteVolume: d('quoteVolume'),
    );
  }

  void dispose() => _http.close();
}
