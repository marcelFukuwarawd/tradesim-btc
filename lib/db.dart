// db.dart — Banco local (SQLite via sqflite). Nada sai do aparelho.
// Tabelas: meta (conta/posição/config), trades (operações fechadas),
// reports (relatórios diários das 21h), bt_candles (cache 1h do backtest).
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'engine.dart';

class ReportRow {
  final String date; // YYYY-MM-DD (horário de São Paulo)
  final double realizedPnl;
  final int trades, wins, losses;
  final double endCash, endEquity, roiPct;
  final int createdTs;

  const ReportRow({
    required this.date,
    required this.realizedPnl,
    required this.trades,
    required this.wins,
    required this.losses,
    required this.endCash,
    required this.endEquity,
    required this.roiPct,
    required this.createdTs,
  });

  Map<String, Object?> toMap() => {
        'date': date,
        'realized_pnl': realizedPnl,
        'trades': trades,
        'wins': wins,
        'losses': losses,
        'end_cash': endCash,
        'end_equity': endEquity,
        'roi_pct': roiPct,
        'created_ts': createdTs,
      };

  factory ReportRow.fromMap(Map<String, Object?> m) => ReportRow(
        date: m['date'] as String,
        realizedPnl: (m['realized_pnl'] as num).toDouble(),
        trades: m['trades'] as int,
        wins: m['wins'] as int,
        losses: m['losses'] as int,
        endCash: (m['end_cash'] as num).toDouble(),
        endEquity: (m['end_equity'] as num).toDouble(),
        roiPct: (m['roi_pct'] as num).toDouble(),
        createdTs: (m['created_ts'] as num).toInt(),
      );
}

class Db {
  Db._();
  static final Db I = Db._();
  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      join(dir, 'tradesim_btc.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute(
            'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute('''
          CREATE TABLE trades (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_time INTEGER NOT NULL,
            exit_time INTEGER NOT NULL,
            qty REAL NOT NULL,
            entry_px REAL NOT NULL,
            exit_px REAL NOT NULL,
            pnl REAL NOT NULL,
            pnl_pct REAL NOT NULL,
            reason TEXT NOT NULL
          )''');
        await db
            .execute('CREATE INDEX idx_trades_exit ON trades(exit_time)');
        await db.execute('''
          CREATE TABLE reports (
            date TEXT PRIMARY KEY,
            realized_pnl REAL NOT NULL,
            trades INTEGER NOT NULL,
            wins INTEGER NOT NULL,
            losses INTEGER NOT NULL,
            end_cash REAL NOT NULL,
            end_equity REAL NOT NULL,
            roi_pct REAL NOT NULL,
            created_ts INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE bt_candles (
            open_time INTEGER PRIMARY KEY,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL NOT NULL
          )''');
      },
    );
  }

  // ------------------------------------------------------------ meta
  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<double?> getMetaDouble(String key) async {
    final v = await getMeta(key);
    return v == null ? null : double.tryParse(v);
  }

  Future<int?> getMetaInt(String key) async {
    final v = await getMeta(key);
    return v == null ? null : int.tryParse(v);
  }

  Future<bool?> getMetaBool(String key) async {
    final v = await getMeta(key);
    return v == null ? null : v == '1';
  }

  Future<void> putMeta(String key, String value) async {
    final db = await database;
    await db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> putMetaDouble(String key, double value) => putMeta(key, value.toString());
  Future<void> putMetaInt(String key, int value) => putMeta(key, value.toString());
  Future<void> putMetaBool(String key, bool value) => putMeta(key, value ? '1' : '0');

  // ---------------------------------------------------------- trades
  Future<int> insertTrade(Trade t) async {
    final db = await database;
    final m = t.toMap()..remove('id');
    return db.insert('trades', m);
  }

  Future<List<Trade>> allTrades({int limit = 500}) async {
    final db = await database;
    final rows = await db.query('trades', orderBy: 'exit_time DESC', limit: limit);
    return rows.map(Trade.fromMap).toList();
  }

  Future<List<Trade>> tradesBetween(int fromMs, int toMs) async {
    final db = await database;
    final rows = await db.query('trades',
        where: 'exit_time >= ? AND exit_time < ?',
        whereArgs: [fromMs, toMs],
        orderBy: 'exit_time ASC');
    return rows.map(Trade.fromMap).toList();
  }

  Future<int> tradeCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM trades');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<double> totalRealizedPnl() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COALESCE(SUM(pnl), 0) s FROM trades');
    return (r.first['s'] as num?)?.toDouble() ?? 0;
  }

  Future<int> winCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM trades WHERE pnl > 0');
    return (r.first['c'] as int?) ?? 0;
  }

  // --------------------------------------------------------- reports
  Future<void> upsertReport(ReportRow r) async {
    final db = await database;
    await db.insert('reports', r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ReportRow?> reportForDate(String date) async {
    final db = await database;
    final rows = await db.query('reports', where: 'date = ?', whereArgs: [date], limit: 1);
    return rows.isEmpty ? null : ReportRow.fromMap(rows.first);
  }

  Future<List<ReportRow>> allReports() async {
    final db = await database;
    final rows = await db.query('reports', orderBy: 'date DESC');
    return rows.map(ReportRow.fromMap).toList();
  }

  // ------------------------------------------- cache 1h p/ backtest
  Future<void> cacheCandles1h(List<Candle> candles) async {
    final db = await database;
    final batch = db.batch();
    for (final c in candles) {
      batch.insert(
          'bt_candles',
          {
            'open_time': c.openTime,
            'open': c.open,
            'high': c.high,
            'low': c.low,
            'close': c.close,
            'volume': c.volume,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Candle>> cachedCandles1h() async {
    final db = await database;
    final rows = await db.query('bt_candles', orderBy: 'open_time ASC');
    return rows
        .map((m) => Candle(
              m['open_time'] as int,
              (m['open'] as num).toDouble(),
              (m['high'] as num).toDouble(),
              (m['low'] as num).toDouble(),
              (m['close'] as num).toDouble(),
              (m['volume'] as num).toDouble(),
            ))
        .toList();
  }

  /// Apaga TUDO (botão "Zerar simulação").
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('trades');
    await db.delete('reports');
    await db.delete('meta');
    await db.delete('bt_candles');
  }
}

/// Chave única de estado da conta (JSON na tabela meta, chave "account").
const String kAccountMetaKey = 'account';

class AccountState {
  final Portfolio portfolio;
  final int lastProcessed5mMs;

  const AccountState({required this.portfolio, required this.lastProcessed5mMs});

  String encode() => jsonEncode({
        'portfolio': portfolio.toMap(),
        'last_processed_5m': lastProcessed5mMs,
      });

  static AccountState? decode(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return AccountState(
        portfolio: Portfolio.fromMap(Map<String, Object?>.from(m['portfolio'] as Map)),
        lastProcessed5mMs: (m['last_processed_5m'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
