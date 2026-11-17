package com.tradesim.btc_trader_sim

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews

/**
 * Widget 5x5 (TradeSim BTC).
 *
 * Os dados são gravados pelo app Flutter via package:home_widget no
 * SharedPreferences "HomeWidgetPreferences". Aqui apenas lemos e exibimos.
 * Toque no widget abre o app.
 */
class TradeWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.tradesim_widget).apply {
                setTextViewText(R.id.widget_price, prefs.getString("price", null) ?: "—")
                setTextViewText(R.id.widget_pnl, prefs.getString("pnl_today", null) ?: "Hoje: —")
                setTextViewText(R.id.widget_cash, prefs.getString("cash", null) ?: "Caixa: —")
                setTextViewText(R.id.widget_roi, prefs.getString("roi", null) ?: "ROI total: —")
                setTextViewText(
                    R.id.widget_position,
                    prefs.getString("position", null) ?: "Zerado — aguardando sinal"
                )
                setTextViewText(R.id.widget_updated, prefs.getString("updated", null) ?: "--:--")

                // Colore o P&L de verde/vermelho quando possível
                val pnl = prefs.getString("pnl_today", "") ?: ""
                val pnlColor = when {
                    pnl.contains("+") -> Color.parseColor("#2EBD85")
                    pnl.contains("-") -> Color.parseColor("#F6465D")
                    else -> Color.parseColor("#F0B90B")
                }
                setTextColor(R.id.widget_pnl, pnlColor)

                // Toque abre o app
                val intent = Intent(context, MainActivity::class.java)
                val pi = PendingIntent.getActivity(
                    context, 0, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                setOnClickPendingIntent(R.id.widget_root, pi)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"
    }
}
