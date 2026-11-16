package au.local.shieldamp;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

final class SendspinSpectrumTest {
    private static void require(boolean condition) {
        if (!condition) throw new AssertionError();
    }

    private static ByteBuffer tone(int frames, int bin, boolean antiPhase) {
        ByteBuffer pcm = ByteBuffer.allocate(frames * 4 + 8).order(ByteOrder.LITTLE_ENDIAN);
        pcm.position(8);
        for (int i = 0; i < frames; i++) {
            short value = (short)(16384 * Math.sin(i * bin * 2.0 * Math.PI / 2048));
            pcm.putShort(value).putShort((short)(antiPhase ? -value : value));
        }
        return pcm;
    }

    private static int peak(float[] bands) {
        int bin = 0;
        for (int i = 1; i < bands.length; i++) if (bands[i] > bands[bin]) bin = i;
        return bin;
    }

    public static void main(String[] args) {
        SendspinSpectrum spectrum = new SendspinSpectrum();
        ByteBuffer bass = tone(4096, 12, true);
        int originalPosition = bass.position();
        spectrum.append(bass, 8, 4096 * 4, 0);
        require(bass.position() == originalPosition);
        require(spectrum.sample(2047) == null);
        require(spectrum.sample(4097) == null);
        SendspinSpectrum.Sample low = spectrum.sample(2048);
        require(low.frame == 2048 && Math.abs(low.rms - 0.353553) < 0.00005);
        require(Math.abs(low.bands[peak(low.bands)] - 0.5) < 0.00005);
        ByteBuffer high = tone(71000, 128, false);
        long at = 5000;
        spectrum.append(high, 8, 71000 * 4, at);
        require(spectrum.sample(4096) == null);
        require(spectrum.sample(at + 2048) == null);
        SendspinSpectrum.Sample treble = spectrum.sample(at + 70000);
        require(peak(treble.bands) > peak(low.bands));
        require(Math.abs(treble.bands[peak(treble.bands)] - 0.5) < 0.00005);
        spectrum.reset();
        require(spectrum.sample(at + 70000) == null);
        spectrum.append(ByteBuffer.allocate(2048 * 4), 0, 2048 * 4, 0);
        SendspinSpectrum.Sample silent = spectrum.sample(2048);
        require(silent.rms == 0 && silent.bands[peak(silent.bands)] == 0);
        System.out.println("Stereo spectrum passed phase, frequency, RMS, ring, playback bounds, reset and silence checks.");
    }
}
