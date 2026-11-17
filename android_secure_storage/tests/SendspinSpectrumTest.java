package au.local.shieldamp;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

final class SendspinSpectrumTest {
    private static void require(boolean condition) {
        if (!condition) throw new AssertionError();
    }

    private static ByteBuffer tone(int frames, int bin, boolean antiPhase) {
        return tone(frames, bin, 2, antiPhase);
    }

    private static ByteBuffer tone(int frames, int bin, int channels, boolean antiPhase) {
        ByteBuffer pcm = ByteBuffer.allocate(frames * channels * 2 + 8).order(ByteOrder.LITTLE_ENDIAN);
        pcm.position(8);
        for (int i = 0; i < frames; i++) {
            short value = (short)(16384 * Math.sin(i * bin * 2.0 * Math.PI / 2048));
            pcm.putShort(value);
            if (channels == 2) pcm.putShort((short)(antiPhase ? -value : value));
        }
        return pcm;
    }

    private static int peak(float[] bands) {
        int bin = 0;
        for (int i = 1; i < bands.length; i++) if (bands[i] > bands[bin]) bin = i;
        return bin;
    }

    private static void requireValidBands(SendspinSpectrum.Sample sample, int sampleRate) {
        require(sample != null && sample.bands.length == 16);
        for (int band = 0; band < sample.bands.length; band++) {
            float value = sample.bands[band];
            require(Float.isFinite(value) && value >= 0 && value <= 1);
            double lowerHz = 20.0 * Math.pow(500.0, band / 16.0);
            if (lowerHz >= sampleRate / 2.0) require(value == 0);
        }
    }

    private static void variableRates() {
        for (int sampleRate : new int[] {8000, 11025, 16000, 48000, 192000}) {
            for (int channels = 1; channels <= 2; channels++) {
                SendspinSpectrum spectrum = new SendspinSpectrum(sampleRate, channels);
                int bin = (int) Math.round(1000.0 * 2048 / sampleRate);
                ByteBuffer pcm = tone(2048, bin, channels, true);
                spectrum.append(pcm, 8, 2048 * channels * 2, 0);
                SendspinSpectrum.Sample sample = spectrum.sample(2048);
                requireValidBands(sample, sampleRate);
                require(Math.abs(sample.rms - 0.353553) < 0.00005);
                require(Math.abs(sample.bands[peak(sample.bands)] - 0.5) < 0.0001);
                double frequency = bin * sampleRate / 2048.0;
                int expectedBand = 0;
                while (expectedBand < 15
                        && frequency >= 20.0 * Math.pow(500.0, (expectedBand + 1) / 16.0)) {
                    expectedBand++;
                }
                require(peak(sample.bands) == expectedBand);

                if (sampleRate < 20000) {
                    // Alternating PCM is exactly at Nyquist, not a zero-valued sine.
                    pcm = ByteBuffer.allocate(2048 * channels * 2).order(ByteOrder.LITTLE_ENDIAN);
                    for (int frame = 0; frame < 2048; frame++) {
                        short value = (short) ((frame & 1) == 0 ? 16384 : -16384);
                        for (int channel = 0; channel < channels; channel++) pcm.putShort(value);
                    }
                    spectrum.reset();
                    spectrum.append(pcm, 0, pcm.capacity(), 0);
                    sample = spectrum.sample(2048);
                    requireValidBands(sample, sampleRate);
                    require(sample.rms == 0.5f);
                    // The excluded endpoint leaves Hann-window energy in its adjacent bin.
                    float amplitude = sample.bands[peak(sample.bands)];
                    require(amplitude > 0.49f && amplitude < 0.51f);
                }
            }
        }
    }

    public static void main(String[] args) {
        variableRates();
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
        System.out.println("Spectrum passed mono/stereo sample rates, Nyquist, phase, frequency, RMS, ring, playback bounds, reset and silence checks.");
    }
}
