package dev.podsync.podsync

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    // An episode a widget asked to play, until the Dart side picks it up.
    private var pendingEpisode: String? = null
    private var widgets: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_EPISODE)?.let { id ->
            // The app is already running: tell it straight away.
            if (widgets != null) widgets!!.invokeMethod("episode", id) else pendingEpisode = id
            intent.removeExtra(EXTRA_EPISODE)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 13 and later hide the playback notification, and with it the lock-screen
        // controls, until the person allows notifications.
        intent?.getStringExtra(EXTRA_EPISODE)?.let { pendingEpisode = it; intent.removeExtra(EXTRA_EPISODE) }
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The app tells the home-screen widgets what is playing; a widget can ask it to play an episode.
        widgets = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.podsync/widgets").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        @Suppress("UNCHECKED_CAST")
                        WidgetState.save(this, call.arguments as Map<String, Any?>)
                        WidgetState.updateAll(this)
                        result.success(null)
                    }
                    "pin" -> {
                        // Ask Android to put a widget on the home screen (the person confirms it).
                        val cls = when (call.arguments as String) {
                            "now" -> NowPlayingWidget::class.java
                            "upnext" -> UpNextWidget::class.java
                            else -> PlayPauseWidget::class.java
                        }
                        val mgr = AppWidgetManager.getInstance(this)
                        result.success(
                            Build.VERSION.SDK_INT >= 26 && mgr.isRequestPinAppWidgetSupported &&
                                mgr.requestPinAppWidget(ComponentName(this, cls), null, null)
                        )
                    }
                    "takePending" -> {
                        result.success(pendingEpisode)
                        pendingEpisode = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Choosing a download folder outside the app's own storage needs "All files access".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.podsync/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFilesAccess" ->
                        result.success(Build.VERSION.SDK_INT < 30 || Environment.isExternalStorageManager())
                    "requestAllFilesAccess" -> {
                        if (Build.VERSION.SDK_INT >= 30) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.podsync/update")
            .setMethodCallHandler { call, result ->
                // Installing an APK needs a one-time "allow from this app" switch. "prepare" is
                // asked before the download so the person is not kept waiting for nothing.
                if (call.method == "prepare") {
                    val allowed = Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()
                    if (!allowed) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                        )
                    }
                    result.success(allowed)
                    return@setMethodCallHandler
                }
                if (call.method != "install") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "no path", null)
                    return@setMethodCallHandler
                }
                val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
                val intent = Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                result.success(null)
            }
    }
}
