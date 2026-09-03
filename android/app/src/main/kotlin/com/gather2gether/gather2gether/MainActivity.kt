package com.gather2gether.gather2gether

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.gather2gether/share",
        ).setMethodCallHandler { call, result ->
            if (call.method != "shareText") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val text = call.argument<String>("text")
            if (text.isNullOrBlank()) {
                result.error("invalid_share", "Share text is empty.", null)
                return@setMethodCallHandler
            }
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            startActivity(Intent.createChooser(intent, "Share invitation"))
            result.success(true)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.gather2gether/reminders",
        ).setMethodCallHandler { call, result ->
            val id = call.argument<Int>("id")
            if (id == null) {
                result.error("invalid_reminder", "Reminder id is missing.", null)
                return@setMethodCallHandler
            }
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val reminderIntent = Intent(this, ReminderReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pendingIntent = PendingIntent.getBroadcast(this, id, reminderIntent, flags)
            when (call.method) {
                "cancel" -> {
                    alarmManager.cancel(pendingIntent)
                    result.success(true)
                }
                "schedule" -> {
                    val at = call.argument<Number>("at")?.toLong()
                    val title = call.argument<String>("title")
                    val body = call.argument<String>("body")
                    val eventId = call.argument<String>("eventId")
                    if (at == null || at <= System.currentTimeMillis() || title.isNullOrBlank() || body.isNullOrBlank() || eventId.isNullOrBlank()) {
                        result.error("invalid_reminder", "Reminder details are invalid.", null)
                        return@setMethodCallHandler
                    }
                    if (
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
                    }
                    reminderIntent.putExtra("id", id)
                    reminderIntent.putExtra("title", title)
                    reminderIntent.putExtra("body", body)
                    reminderIntent.putExtra("eventId", eventId)
                    val scheduledIntent = PendingIntent.getBroadcast(this, id, reminderIntent, flags)
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, scheduledIntent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
