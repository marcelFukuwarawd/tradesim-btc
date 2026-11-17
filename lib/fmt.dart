// fmt.dart — formatação de números/datas (sem dependência extra)
library;

String fmtUsd(double v, {int decimals = 2, bool sign = false}) {
  final s = v.abs().toStringAsFixed(decimals);
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  final signStr = v < 0 ? '-' : (sign && v > 0 ? '+' : '');
  return '$signStr\$${parts.length > 1 ? '$intPart,${parts[1]}' : intPart}';
}

String fmtBtc(double v) => v.toStringAsFixed(5);

String fmtPct(double v, {bool sign = true}) =>
    '${sign && v > 0 ? '+' : ''}${v.toStringAsFixed(2)}%';

String fmtCompactUsd(double v) {
  if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
  if (v >= 1e3) return '\$${(v / 1e3).toStringAsFixed(1)}K';
  return fmtUsd(v);
}

const _meses = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez'
];

String fmtDateShort(DateTime dLocal) =>
    '${dLocal.day.toString().padLeft(2, '0')}/${_meses[dLocal.month - 1]}/${dLocal.year}';

String fmtDateTimeShort(DateTime dLocal) =>
    '${fmtDateShort(dLocal)} ${dLocal.hour.toString().padLeft(2, '0')}:${dLocal.minute.toString().padLeft(2, '0')}';

String fmtClock(int msUtc) {
  final d = DateTime.fromMillisecondsSinceEpoch(msUtc, isUtc: true).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Chave de dia local (YYYY-MM-DD) no fuso America/Sao_Paulo — consistente com o relatório das 21h.
String reportDateKey(DateTime dLocal) {
  final y = dLocal.year.toString().padLeft(4, '0');
  final m = dLocal.month.toString().padLeft(2, '0');
  final day = dLocal.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

(int startMs, int endMs) localDayRangeMs(DateTime dLocal) {
  final start = DateTime(dLocal.year, dLocal.month, dLocal.day);
  final end = start.add(const Duration(days: 1));
  return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
}
