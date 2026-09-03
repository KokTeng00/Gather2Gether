package com.gather2gether.gather2gether

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.net.Uri
import android.os.Build

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Event reminders",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val title = intent.getStringExtra("title") ?: "Event reminder"
        val body = intent.getStringExtra("body") ?: "Your event starts soon."
        val eventId = intent.getStringExtra("eventId")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .apply {
                if (eventId != null) {
                    val openEvent = Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse("gather2gether://event/$eventId"),
                        context,
                        MainActivity::class.java,
                    )
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    setContentIntent(PendingIntent.getActivity(context, intent.getIntExtra("id", 0), openEvent, flags))
                }
            }
            .build()
        manager.notify(intent.getIntExtra("id", 0), notification)
    }

    companion object {
        const val CHANNEL_ID = "event_reminders"
    }
}
