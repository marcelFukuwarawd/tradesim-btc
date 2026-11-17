// theme.dart — Identidade visual do TradeSim BTC (inspirada em Binance/TradingView)
import 'package:material_ui/material_ui.dart';

const kBg = Color(0xFF0B0E11);
const kCard = Color(0xFF161A1E);
const kCardLight = Color(0xFF1E2329);
const kBorder = Color(0xFF2B3139);
const kText = Color(0xFFEAECEF);
const kTextSoft = Color(0xFF848E9C);
const kYellow = Color(0xFFF0B90B);
const kGreen = Color(0xFF2EBD85);
const kRed = Color(0xFFF6465D);
const kPurple = Color(0xFFA855F7);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
      primary: kYellow,
      onPrimary: Color(0xFF1E2329),
      surface: kCard,
      onSurface: kText,
      error: kRed,
    ),
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kText,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: kCard,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: kBorder, width: 0.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kCard,
      indicatorColor: kYellow.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? kYellow : kTextSoft,
            size: 22,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
                color: states.contains(WidgetState.selected) ? kYellow : kTextSoft,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
      elevation: 0,
      height: 62,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kCardLight,
      contentTextStyle: TextStyle(color: kText),
      behavior: SnackBarBehavior.floating,
    ),
    dividerColor: kBorder,
  );
}

/// Cartão padrão do app
class CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const CardBox({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder, width: 0.6),
        ),
        child: child,
      );
}

/// Rótulo de seção em "caps" — ex.: "CONTA", "BACKTEST 90 DIAS"
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: kTextSoft,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
        ),
      );
}

/// Bloco de estatística (valor + rótulo)
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String? sub;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor = kText,
    this.sub,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: kTextSoft,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (sub != null) ...[
            const SizedBox(height: 1),
            Text(sub!,
                style: const TextStyle(color: kTextSoft, fontSize: 10.5)),
          ],
        ],
      );
}

/// Chip colorido (variação, "SIMULADO", AO VIVO etc.)
class InfoChip extends StatelessWidget {
  final String text;
  final Color color;
  final Color? textColor;
  const InfoChip(this.text,
      {super.key, required this.color, this.textColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.7),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: textColor ?? color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8),
        ),
      );
}
