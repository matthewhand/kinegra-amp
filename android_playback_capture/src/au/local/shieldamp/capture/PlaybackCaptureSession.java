package au.local.shieldamp.capture;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioPlaybackCaptureConfiguration;
import android.media.AudioRecord;
import android.media.projection.MediaProjection;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;

/** API 29+ feasibility prototype. Host supplies an already-consented projection.
 * No UI, storage, network, file output, logging, audio playback or PCM export.
 */
public final class PlaybackCaptureSession implements AutoCloseable {
    private final MediaProjection projection;
    private final AudioRecord recorder;
    private final AtomicBoolean running = new AtomicBoolean(true);
    private volatile float level;
    private volatile long lastDataMs = -1;
    private volatile String status = "starting";
    private final MediaProjection.Callback callback = new MediaProjection.Callback() {
        @Override public void onStop() { close(); }
    };

    private PlaybackCaptureSession(MediaProjection p, AudioRecord r) {
        projection = p;
        recorder = r;
    }

    /** Caller must check API level, RECORD_AUDIO permission and projection consent.
     * Exclude this app's UID to avoid feedback when ShieldAmp is also playing.
     */
    public static PlaybackCaptureSession start(MediaProjection projection, int ownUid) {
        if (projection == null || ownUid < 0) throw new IllegalArgumentException("invalid capture inputs");
        final int sampleRate = 44100;
        int minimum = AudioRecord.getMinBufferSize(sampleRate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        if (minimum <= 0) throw new IllegalStateException("audio format unavailable");
        AudioPlaybackCaptureConfiguration config =
                new AudioPlaybackCaptureConfiguration.Builder(projection)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .excludeUid(ownUid).build();
        AudioFormat format = new AudioFormat.Builder().setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_IN_MONO).build();
        AudioRecord record = new AudioRecord.Builder().setAudioFormat(format)
                .setBufferSizeInBytes(Math.max(minimum, 4096))
                .setAudioPlaybackCaptureConfig(config).build();
        if (record.getState() != AudioRecord.STATE_INITIALIZED) {
            record.release();
            throw new IllegalStateException("audio capture unavailable");
        }
        PlaybackCaptureSession session = new PlaybackCaptureSession(projection, record);
        try {
            projection.registerCallback(session.callback, new Handler(Looper.getMainLooper()));
            record.startRecording();
            if (record.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING)
                throw new IllegalStateException("audio capture did not start");
            Thread worker = new Thread(session::run, "shieldamp-playback-envelope");
            worker.setDaemon(true);
            session.status = "capturing";
            worker.start();
            return session;
        } catch (RuntimeException failure) {
            session.running.set(false);
            projection.unregisterCallback(session.callback);
            try { record.stop(); } catch (IllegalStateException ignored) {}
            record.release();
            throw failure;
        }
    }

    private void run() {
        short[] samples = new short[1024];
        try {
            while (running.get()) {
                int n = recorder.read(samples, 0, samples.length);
                if (n <= 0) {
                    if (running.get()) status = "capture_error";
                    break;
                }
                float next = CaptureEnvelope.rms(samples, n);
                if (running.get()) {
                    level = next;
                    lastDataMs = SystemClock.elapsedRealtime();
                }
                Arrays.fill(samples, (short) 0);
            }
        } catch (RuntimeException failure) {
            if (running.get()) status = "capture_error";
        } finally {
            Arrays.fill(samples, (short) 0);
            level = 0f;
            lastDataMs = -1;
            synchronized (this) {
                close();
                recorder.release();
            }
        }
    }

    /** Silence may mean no sound OR a source that Android will not capture. */
    public float currentLevel() {
        long age = SystemClock.elapsedRealtime() - lastDataMs;
        return running.get() && lastDataMs >= 0 && age >= 0 && age <= 500 ? level : 0f;
    }
    public String status() { return status; }
    @Override public synchronized void close() {
        if (!running.getAndSet(false)) return;
        if (!"capture_error".equals(status)) status = "stopped";
        level = 0f;
        lastDataMs = -1;
        try { recorder.stop(); } catch (IllegalStateException ignored) {}
        projection.unregisterCallback(callback);
        projection.stop();
    }
}
