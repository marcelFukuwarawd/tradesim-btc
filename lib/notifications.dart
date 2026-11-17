// notifications.dart — Notificação local (sem Firebase, sem login).
// Agenda o "Relatório TradeSim BTC das 21h" todos os dias no horário de
// São Paulo e mostra o resumo imediatamente quando as 21h chegam com o app aberto.
import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  static const int scheduledReportId = 2100;
  static const int instantReportId = 2199;
  static const String channelId = 'daily_report';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('ic_launcher');
    await plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    const channel = AndroidNotificationChannel(
      channelId,
      'Relatório diário das 21h',
      description: 'Resumo de ganhos e perdas do dia no TradeSim BTC',
      importance: Importance.high,
    );
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  static tz.Location get _saoPaulo => tz.getLocation('America/Sao_Paulo');

  static AndroidNotificationDetails get _details => const AndroidNotificationDetails(
        channelId,
        'Relatório diário das 21h',
        channelDescription: 'Resumo de ganhos e perdas do dia no TradeSim BTC',
        icon: 'ic_launcher',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'TradeSim BTC — relatório das 21h',
      );

  /// Agenda (ou reagenda) a notificação diária das 21h com o corpo informado.
  static Future<void> scheduleDailyReport(String body) async {
    await plugin.cancel(scheduledReportId);
    final now = tz.TZDateTime.now(_saoPaulo);
    var at = tz.TZDateTime(_saoPaulo, now.year, now.month, now.day, 21);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));

    const title = 'TradeSim BTC — Relatório das 21h';
    try {
      await plugin.zonedSchedule(
        scheduledReportId,
        title,
        body,
        at,
        NotificationDetails(android: _details),
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'daily_report',
      );
    } catch (_) {
      // Android 12+ pode negar alarme exato — usa modo inexato (mesmo dia).
      await plugin.zonedSchedule(
        scheduledReportId,
        title,
        body,
        at,
        NotificationDetails(android: _details),
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'daily_report',
      );
    }
  }

  /// Mostra uma notificação imediata (ex.: teste ou relatório das 21h com app aberto).
  static Future<void> showNow(String title, String body) async {
    await plugin.show(
      instantReportId,
      title,
      body,
      NotificationDetails(android: _details),
      payload: 'daily_report',
    );
  }
}
