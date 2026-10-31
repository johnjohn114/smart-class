package com.announcementzone.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class AnnouncementMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) { super.onNewToken(token) }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val title = message.notification?.title ?: message.data["title"] ?: "事項公告區"
        val body = message.notification?.body ?: message.data["body"] ?: "有一則新公告"
        val id = message.data["announcement_id"] ?: ""
        val channelId = "announcement_updates"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channelId, "公告通知", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "事項公告區最新公告推播"
                }
            )
        }
        val target = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (id.isNotBlank()) putExtra("announcement_url", "https://johnjohn114.github.io/smart-class/news.html#announcement-$id")
        }
        val pending = PendingIntent.getActivity(this, id.hashCode(), target, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle(title).setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true).setContentIntent(pending).build()
        NotificationManagerCompat.from(this).notify(id.hashCode(), notification)
    }
}
