package au.local.shieldamp.capture;

/** Convert one bounded synthetic or captured PCM block to a normalized RMS level. */
public final class CaptureEnvelope {
    private CaptureEnvelope() {}
    public static float rms(short[] samples, int count) {
        if (samples == null || count <= 0 || count > samples.length) return 0f;
        double energy = 0;
        for (int i = 0; i < count; i++) {
            double s = samples[i] / 32768.0;
            energy += s * s;
        }
        return (float) Math.min(1.0, Math.sqrt(energy / count));
    }
}
