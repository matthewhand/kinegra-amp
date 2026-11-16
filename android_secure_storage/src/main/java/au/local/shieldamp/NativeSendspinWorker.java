package au.local.shieldamp;

import android.content.Context;
import java.nio.ByteBuffer;
import org.json.JSONException;
import org.json.JSONObject;

/** Service-thread owner. The activity never advances or opens its session. */
final class NativeSendspinWorker implements AutoCloseable {
    static { System.loadLibrary("shield_sendspin_arm64"); }

    private final Thread thread = Thread.currentThread();
    private final ServiceSendspinVault vault;
    private final ByteBuffer pending = ByteBuffer.allocateDirect(4096);
    private long session;
    private long generation = -1;
    private SendspinAudioTrack output;
    private boolean playbackAllowed;
    private boolean awaitingPairing;
    private int appGainPercent = 100;
    private boolean analysisEnabled;

    void setAnalysisEnabled(boolean enabled) {
        requireWorkerThread();
        if (analysisEnabled == enabled) return;
        analysisEnabled = enabled;
        if (output != null) output.setAnalysisEnabled(enabled);
    }

    long currentGeneration() { return generation; }
    long reportedAtNs() { return output == null ? 0 : output.reportedAtNs(); }

    SendspinSpectrum.Sample analysisSample() {
        requireWorkerThread();
        return output == null || !playbackAllowed ? null : output.analysisSample();
    }

    NativeSendspinWorker(Context context) {
        vault = new ServiceSendspinVault(context);
        pending.limit(0);
    }

    boolean open(String endpoint) {
        requireWorkerThread();
        if (session != 0 || endpoint == null || endpoint.isEmpty()) return false;
        session = openNative(endpoint, vault);
        return session != 0;
    }

    boolean tick() {
        requireWorkerThread();
        if (session == 0) return false;
        try {
            if (tickNative(session) && pump()) return true;
        } catch (RuntimeException unavailable) {
            // Unsupported output or unavailable native playback timestamps.
        }
        close();
        return false;
    }

    void permitPlayback(boolean permit) {
        requireWorkerThread();
        playbackAllowed = permit;
        if (output != null) output.permit(permit);
    }

    void setAppGainPercent(int percent) {
        requireWorkerThread();
        appGainPercent = percent;
        if (output != null) output.setAppGainPercent(percent);
    }

    long queuedFrames() {
        requireWorkerThread();
        return (output == null ? 0 : output.queuedFrames()) + pending.remaining() / 4;
    }

    private boolean pump() {
        long next = generationNative(session);
        if (next < 0) {
            discardOutput();
            return true;
        }
        if (next != generation) {
            discardOutput();
            output = new SendspinAudioTrack();
            output.setAppGainPercent(appGainPercent);
            output.setAnalysisEnabled(analysisEnabled);
            output.permit(playbackAllowed);
            generation = next;
            if (!ackNative(session, generation)) {
                discardOutput();
                return true;
            }
        }
        if (!playbackAllowed) return true;
        int frames = output.playingFrames();
        if (frames > 0) {
            long age = output.timestampAgeNs();
            if (age >= 0 && age <= 250_000_000L) {
                if (playedNative(session, generation, frames, age)) {
                    output.committed(frames);
                } else if (generationNative(session) != generation) {
                    discardOutput();
                    return true;
                } else return false;
            }
        }
        if (!pending.hasRemaining()) {
            pending.clear();
            int count = readNative(session, generation, pending, pending.capacity());
            if (count == -2) {
                discardOutput();
                return true;
            }
            if (count < 0) return false;
            pending.limit(count);
        }
        if (pending.hasRemaining()) {
            int before = pending.position();
            int written = writeNative(session, generation, output, pending, pending.remaining());
            if (written == -2) {
                discardOutput();
                return true;
            }
            if (written < 0 || written % 4 != 0 || pending.position() - before != written)
                return false;
        }
        output.update();
        return true;
    }

    private void discardOutput() {
        if (output != null) {
            output.close();
            output = null;
        }
        generation = -1;
        pending.position(0);
        pending.limit(0);
    }

    boolean command(String action, int value) {
        requireWorkerThread();
        return session != 0 && commandNative(session, action, value);
    }

    boolean confirm() {
        requireWorkerThread();
        if (session == 0 || awaitingPairing) return false;
        awaitingPairing = confirmNative(session);
        return awaitingPairing;
    }

    JSONObject snapshot() {
        requireWorkerThread();
        try {
            JSONObject state = new JSONObject(snapshotNative(session));
            if (!state.optBoolean("pairing_window")) awaitingPairing = false;
            state.put("source", "ma");
            String display = "connecting";
            if (state.optBoolean("paired")) {
                if (output == null) display = "paired";
                else if (!playbackAllowed) display = "paused";
                else display = output.progressing() ? "playing" : "buffering";
            }
            state.put("state", display);
            state.put("stream_active", output != null && playbackAllowed);
            state.put("underruns", output == null ? 0 : output.underrunCount());
            state.put("rebuffers", output == null ? 0 : output.rebufferCount());
            long frames = queuedFrames() + state.optInt("ring_bytes", 0) / 4;
            state.remove("ring_bytes");
            state.put("queued_ms", frames * 1000 / 48000);
            return state;
        } catch (JSONException error) {
            throw new IllegalStateException("Invalid playback worker state", error);
        }
    }

    boolean trusted() {
        requireWorkerThread();
        return session != 0 && trustedNative(session);
    }

    @Override public void close() {
        requireWorkerThread();
        discardOutput();
        playbackAllowed = false;
        awaitingPairing = false;
        if (session == 0) return;
        final long handle = session;
        session = 0;
        closeNative(handle);
    }

    private void requireWorkerThread() {
        if (Thread.currentThread() != thread) throw new IllegalStateException("Sendspin worker thread required");
    }

    private static native long openNative(String endpoint, ServiceSendspinVault vault);
    private static native boolean tickNative(long session);
    private static native boolean trustedNative(long session);
    private static native boolean commandNative(long session, String command, int value);
    private static native boolean confirmNative(long session);
    private static native String snapshotNative(long session);
    private static native void closeNative(long session);
    private static native long generationNative(long session);
    private static native boolean ackNative(long session, long generation);
    private static native int readNative(long session, long generation, ByteBuffer direct, int limit);
    private static native int writeNative(long session, long generation, SendspinAudioTrack output,
                                          ByteBuffer direct, int bytes);
    private static native boolean playedNative(long session, long generation, int frames, long timestampAgeNs);
}
