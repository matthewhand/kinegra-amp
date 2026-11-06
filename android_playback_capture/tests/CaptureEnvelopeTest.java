package au.local.shieldamp.capture;
public final class CaptureEnvelopeTest {
    private static void check(boolean ok, String name) {
        if (!ok) throw new AssertionError(name);
        System.out.println("PASS_" + name);
    }
    public static void main(String[] args) {
        check(CaptureEnvelope.rms(null, 4)==0, "null");
        check(CaptureEnvelope.rms(new short[0], 0)==0, "empty");
        check(CaptureEnvelope.rms(new short[1], 2)==0, "bounds");
        check(CaptureEnvelope.rms(new short[64], 64)==0, "silence");
        check(CaptureEnvelope.rms(new short[]{-32768, -32768}, 2)==1, "minimum_pcm");
        float value=CaptureEnvelope.rms(new short[]{16384, -16384, 0, 0}, 4);
        check(Math.abs(value-0.3535534f)<0.00001, "synthetic_half_amplitude");
        check(CaptureEnvelope.rms(new short[]{0, -32768}, 1)==0, "count_is_honored");
    }
}
