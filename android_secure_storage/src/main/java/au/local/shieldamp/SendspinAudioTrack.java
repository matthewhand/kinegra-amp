package au.local.shieldamp;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTimestamp;
import android.media.AudioTrack;
import java.nio.ByteBuffer;

/** Created and used only by the established playback service's owner thread. */
final class SendspinAudioTrack implements AutoCloseable {
    private static final int RATE = 48000;
    private static final int FRAME_BYTES = 4;
    private static final int PREFILL = 18432;
    private static final int BUFFER = 24000;
    private final AudioTimestamp time = new AudioTimestamp();
    private final AudioTrack track;
    private long submitted;
    private long reported;
    private int underruns;
    private boolean playing;
    private boolean permitted;
    private long lastProgressNs;
    private long reportedAtNs;
    private int rebuffers;
    private SendspinSpectrum spectrum;

    void setAnalysisEnabled(boolean enabled) {
        if (enabled && spectrum == null) spectrum = new SendspinSpectrum();
        else if (!enabled && spectrum != null) spectrum = null;
    }

    SendspinSpectrum.Sample analysisSample() {
        return spectrum == null || !playing ? null : spectrum.sample(reported);
    }

    long reportedAtNs() { return reportedAtNs; }
    int underrunCount() { return track.getUnderrunCount(); }
    int rebufferCount() { return rebuffers; }

    SendspinAudioTrack() {
        int minimum = AudioTrack.getMinBufferSize(
                RATE, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT);
        if (minimum <= 0) throw new IllegalStateException("PCM format unavailable");
        track = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioFormat(new AudioFormat.Builder().setSampleRate(RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(Math.max(minimum, BUFFER * FRAME_BYTES)).build();
        if (track.getState() != AudioTrack.STATE_INITIALIZED) {
            track.release();
            throw new IllegalStateException("PCM sink unavailable");
        }
    }

    /** Called from the generation-locked native gate. Never calls native code. */
    int writePcm(ByteBuffer bytes, int size) {
        int start = bytes.position();
        int written = track.write(bytes, size, AudioTrack.WRITE_NON_BLOCKING);
        if (written > 0 && written % FRAME_BYTES == 0) {
            if (spectrum != null) spectrum.append(bytes, start, written, submitted);
            submitted += written / FRAME_BYTES;
        }
        return written;
    }

    int playingFrames() {
        if (!playing || !track.getTimestamp(time)) return 0;
        // Use a monotonic playback timestamp and extend its 32-bit frame cursor.
        long lower = time.framePosition & 0xffffffffL;
        long extended = (reported & ~0xffffffffL) | lower;
        if (extended + 0x80000000L < reported) extended += 0x100000000L;
        return extended > reported && extended <= submitted && extended - reported <= Integer.MAX_VALUE
                ? (int) (extended - reported) : 0;
    }

    long timestampAgeNs() { return System.nanoTime() - time.nanoTime; }

    void committed(int frames) {
        reported += frames;
        reportedAtNs = time.nanoTime;
        lastProgressNs = System.nanoTime();
    }

    void setAppGainPercent(int percent) {
        if (track.setVolume(percent / 100f) != AudioTrack.SUCCESS) {
            throw new IllegalStateException("PCM sink rejected Kinegra Amp volume");
        }
    }

    long queuedFrames() { return submitted - reported; }

    boolean progressing() {
        long age = System.nanoTime() - reportedAtNs;
        return playing && reported > 0 && age >= 0 && age <= 500_000_000L;
    }

    void permit(boolean allow) {
        permitted = allow;
        if (!allow) pause();
    }

    void update() {
        if (!permitted) return;
        if (playing) {
            if (track.getUnderrunCount() > underruns) {
                rebuffers += 1;
                pause();
            } else if (System.nanoTime() - lastProgressNs > 4_000_000_000L) {
                throw new IllegalStateException("AudioTrack playback timestamp unavailable");
            }
        }
        if (!playing && queuedFrames() >= PREFILL) {
            track.play();
            underruns = track.getUnderrunCount();
            lastProgressNs = System.nanoTime();
            playing = true;
        }
    }

    private void pause() {
        if (!playing) return;
        track.pause();
        playing = false;
    }

    /** Completely dispose old queued bytes before acknowledging a generation change. */
    @Override public void close() { track.release(); }
}
