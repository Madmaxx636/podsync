package dev.podsync.podsync

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.view.KeyEvent
import android.widget.RemoteViews
import org.json.JSONArray

/** What the app last told the widgets: the episode that is playing and the next ones in Up Next. */
object WidgetState {
    private const val FILE = "podsync_widgets"

    fun save(ctx: Context, values: Map<String, Any?>) {
        val e = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
        for ((k, v) in values) when (v) {
            is Boolean -> e.putBoolean(k, v)
            is Number -> e.putLong(k, v.toLong()) // the channel sends small numbers as Int, big as Long
            is String -> e.putString(k, v)
            null -> e.remove(k)
        }
        e.apply()
    }

    fun prefs(ctx: Context) = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun updateAll(ctx: Context) {
        val mgr = AppWidgetManager.getInstance(ctx)
        for (cls in listOf(NowPlayingWidget::class.java, UpNextWidget::class.java, PlayPauseWidget::class.java)) {
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, cls))
            if (ids.isNotEmpty()) {
                ctx.sendBroadcast(
                    Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                        .setClass(ctx, cls)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                )
            }
        }
    }
}

const val ACTION_PLAY_PAUSE = "dev.podsync.widget.PLAY_PAUSE"
const val ACTION_REWIND = "dev.podsync.widget.REWIND"
const val ACTION_FORWARD = "dev.podsync.widget.FORWARD"
const val ACTION_NEXT = "dev.podsync.widget.NEXT"
const val EXTRA_EPISODE = "podsync.episode"

private fun broadcast(ctx: Context, action: String, code: Int): PendingIntent =
    PendingIntent.getBroadcast(
        ctx, code,
        Intent(ctx, WidgetActionReceiver::class.java).setAction(action),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )

/** Opens PodSync; with an episode id it plays that episode. */
private fun openApp(ctx: Context, code: Int, episode: String? = null): PendingIntent {
    val i = Intent(ctx, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    if (episode != null) i.putExtra(EXTRA_EPISODE, episode)
    return PendingIntent.getActivity(ctx, code, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
}

/** The cover as a small rounded bitmap, or null when there is none. */
private fun cover(path: String?, px: Int): Bitmap? {
    if (path.isNullOrEmpty()) return null
    return try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= px) sample *= 2
        val src = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val out = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        c.drawRoundRect(RectF(0f, 0f, px.toFloat(), px.toFloat()), px * 0.14f, px * 0.14f, p)
        p.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        val side = minOf(src.width, src.height)
        c.drawBitmap(
            src,
            android.graphics.Rect((src.width - side) / 2, (src.height - side) / 2, (src.width + side) / 2, (src.height + side) / 2),
            RectF(0f, 0f, px.toFloat(), px.toFloat()), p
        )
        out
    } catch (e: Exception) { null }
}

private fun playIcon(playing: Boolean) = if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play

class NowPlayingWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        val s = WidgetState.prefs(ctx)
        val has = s.getBoolean("has", false)
        val v = RemoteViews(ctx.packageName, R.layout.widget_now_playing)
        v.setTextViewText(R.id.title, if (has) s.getString("title", "") else "Nothing playing")
        v.setTextViewText(R.id.podcast, if (has) s.getString("podcast", "") else "Tap play to start Up Next")
        val art = cover(s.getString("art", null), 240)
        if (art != null) v.setImageViewBitmap(R.id.art, art) else v.setImageViewResource(R.id.art, R.drawable.ic_widget_logo)
        val dur = s.getLong("durationMs", 0)
        v.setProgressBar(R.id.progress, 1000, if (dur > 0) (s.getLong("positionMs", 0) * 1000 / dur).toInt().coerceIn(0, 1000) else 0, false)
        v.setImageViewResource(R.id.play_pause, playIcon(s.getBoolean("playing", false)))
        v.setOnClickPendingIntent(R.id.play_pause, broadcast(ctx, ACTION_PLAY_PAUSE, 1))
        v.setOnClickPendingIntent(R.id.rewind, broadcast(ctx, ACTION_REWIND, 2))
        v.setOnClickPendingIntent(R.id.forward, broadcast(ctx, ACTION_FORWARD, 3))
        v.setOnClickPendingIntent(R.id.next, broadcast(ctx, ACTION_NEXT, 4))
        v.setOnClickPendingIntent(R.id.art, openApp(ctx, 5))
        v.setOnClickPendingIntent(R.id.title, openApp(ctx, 5))
        for (id in ids) mgr.updateAppWidget(id, v)
    }
}

class PlayPauseWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        val s = WidgetState.prefs(ctx)
        val has = s.getBoolean("has", false)
        val v = RemoteViews(ctx.packageName, R.layout.widget_play_pause)
        v.setTextViewText(R.id.title, if (has) s.getString("title", "") else "PodSync")
        v.setTextViewText(R.id.podcast, if (has) s.getString("podcast", "") else "Tap to play Up Next")
        v.setImageViewResource(R.id.play_pause, playIcon(s.getBoolean("playing", false)))
        v.setOnClickPendingIntent(R.id.play_pause, broadcast(ctx, ACTION_PLAY_PAUSE, 11))
        v.setOnClickPendingIntent(R.id.open, openApp(ctx, 12))
        for (id in ids) mgr.updateAppWidget(id, v)
    }
}

class UpNextWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        val s = WidgetState.prefs(ctx)
        val items = try { JSONArray(s.getString("queue", "[]")) } catch (e: Exception) { JSONArray() }
        val total = s.getLong("queueCount", items.length().toLong()).toInt()
        val v = RemoteViews(ctx.packageName, R.layout.widget_up_next)
        v.setTextViewText(R.id.heading, if (total > 0) "Up Next · $total" else "Up Next")
        v.setOnClickPendingIntent(R.id.header, openApp(ctx, 20))
        v.setTextViewText(R.id.empty, "Nothing queued. Add episodes in PodSync.")
        v.setViewVisibility(R.id.empty, if (items.length() == 0) android.view.View.VISIBLE else android.view.View.GONE)
        val rows = intArrayOf(R.id.row1, R.id.row2, R.id.row3, R.id.row4)
        val titles = intArrayOf(R.id.title1, R.id.title2, R.id.title3, R.id.title4)
        val subs = intArrayOf(R.id.sub1, R.id.sub2, R.id.sub3, R.id.sub4)
        for (i in rows.indices) {
            if (i < items.length()) {
                val o = items.getJSONObject(i)
                v.setViewVisibility(rows[i], android.view.View.VISIBLE)
                v.setTextViewText(titles[i], o.optString("title"))
                v.setTextViewText(subs[i], o.optString("sub"))
                v.setOnClickPendingIntent(rows[i], openApp(ctx, 30 + i, o.optString("id")))
            } else {
                v.setViewVisibility(rows[i], android.view.View.GONE)
            }
        }
        for (id in ids) mgr.updateAppWidget(id, v)
    }
}

/** Widget buttons become media keys sent to PodSync's own media session (they start it if it was closed). */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val key = when (intent.action) {
            ACTION_PLAY_PAUSE -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            ACTION_REWIND -> KeyEvent.KEYCODE_MEDIA_REWIND
            ACTION_FORWARD -> KeyEvent.KEYCODE_MEDIA_FAST_FORWARD
            ACTION_NEXT -> KeyEvent.KEYCODE_MEDIA_NEXT
            else -> return
        }
        for (action in intArrayOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            ctx.sendBroadcast(
                Intent(Intent.ACTION_MEDIA_BUTTON)
                    .setComponent(ComponentName(ctx, "com.ryanheise.audioservice.MediaButtonReceiver"))
                    .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(action, key))
            )
        }
    }
}
