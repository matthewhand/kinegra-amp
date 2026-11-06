package au.local.shieldamp.capture;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Process;

/** Private, non-restarting capture service; no raw audio leaves memory. */
public final class CaptureService extends Service {
    static final String START = "au.local.shieldamp.capture.START";
    private static final String STOP = "au.local.shieldamp.capture.STOP";
    private static final String CHANNEL = "shieldamp_capture";
    static volatile String state = "stopped";
    static volatile PlaybackCaptureSession session;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable poll = new Runnable() {
        @Override public void run() {
            PlaybackCaptureSession current = session;
            if (current == null || !"capturing".equals(current.status())) {
                state = current == null ? "stopped" : current.status();
                stopSelf();
            } else handler.postDelayed(this, 500);
        }
    };
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null || STOP.equals(intent.getAction())) { state = "stopped"; stopSelf(); return START_NOT_STICKY; }
        if (session != null) return START_NOT_STICKY;
        if (!START.equals(intent.getAction()) || Build.VERSION.SDK_INT < 29) {
            state = "unavailable"; stopSelf(); return START_NOT_STICKY;
        }
        MediaProjection projection = null;
        try {
            startVisibleService();
            Intent result = intent.getParcelableExtra("result_data");
            int code = intent.getIntExtra("result_code", 0);
            if (result == null) throw new IllegalStateException("missing consent result");
            MediaProjectionManager manager = (MediaProjectionManager) getSystemService(Context.MEDIA_PROJECTION_SERVICE);
            if (manager == null) throw new IllegalStateException("projection unavailable");
            projection = manager.getMediaProjection(code, result);
            if (projection == null) throw new IllegalStateException("projection unavailable");
            session = PlaybackCaptureSession.start(projection, Process.myUid());
            state = "capturing";
            handler.postDelayed(poll, 500);
        } catch (RuntimeException failure) {
            if (projection != null) projection.stop();
            state = "capture_error";
            stopSelf();
        }
        return START_NOT_STICKY;
    }
    private void startVisibleService() {
        NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) throw new IllegalStateException("notification unavailable");
        manager.createNotificationChannel(new NotificationChannel(CHANNEL, "Playback visualization", NotificationManager.IMPORTANCE_LOW));
        Intent stop = new Intent(this, CaptureService.class).setAction(STOP);
        PendingIntent stopAction = PendingIntent.getService(this, 1, stop, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification notification = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("ShieldAmp audio visualization active")
                .setContentText("Capturing permitted playback to create local visuals")
                .setOngoing(true).addAction(new Notification.Action.Builder(null, "Stop", stopAction).build()).build();
        if (Build.VERSION.SDK_INT >= 29) startForeground(7361, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        else startForeground(7361, notification);
    }
    @Override public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        PlaybackCaptureSession old = session;
        session = null;
        if (old != null) old.close();
        if (!"capture_error".equals(state)) state = "stopped";
        stopForeground(true);
        super.onDestroy();
    }
}
