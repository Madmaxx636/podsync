package dev.podsync.podsync

import android.Manifest
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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 13 and later hide the playback notification, and with it the lock-screen
        // controls, until the person allows notifications.
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
