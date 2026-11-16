package au.local.shieldamp;

import java.nio.ByteBuffer;

/** Stereo spectrum of the PCM that has reached the AudioTrack playback head. */
final class SendspinSpectrum {
    private static final int SAMPLE_RATE = 48000;
    private static final int WINDOW_SIZE = 2048;
    private static final int RETAINED_FRAMES = 65536;
    private static final int RING_MASK = RETAINED_FRAMES - 1;
    private static final int BAND_COUNT = 16;
    private static final double BAND_RATIO = Math.pow(500.0, 1.0 / BAND_COUNT);

    private final short[] left = new short[RETAINED_FRAMES];
    private final short[] right = new short[RETAINED_FRAMES];
    private final double[] real = new double[WINDOW_SIZE];
    private final double[] imaginary = new double[WINDOW_SIZE];
    private final double[] window = new double[WINDOW_SIZE];
    private final double[] cosine = new double[WINDOW_SIZE / 2];
    private final double[] sine = new double[WINDOW_SIZE / 2];
    private final int[] reverseIndex = new int[WINDOW_SIZE];
    private final int[] bandStarts = new int[BAND_COUNT + 1];
    private final double windowScale;
    private long firstRetained;
    private long nextFrame;

    static final class Sample {
        final float[] bands;
        final float rms;
        final long frame;

        Sample(float[] bands, float rms, long frame) {
            this.bands = bands;
            this.rms = rms;
            this.frame = frame;
        }
    }

    SendspinSpectrum() {
        double windowSum = 0.0;
        int shift = Integer.numberOfLeadingZeros(WINDOW_SIZE - 1);
        for (int i = 0; i < WINDOW_SIZE; i++) {
            window[i] = 0.5 - 0.5 * Math.cos(2.0 * Math.PI * i / (WINDOW_SIZE - 1));
            windowSum += window[i];
            reverseIndex[i] = Integer.reverse(i) >>> shift;
        }
        windowScale = 1.0 / windowSum;
        for (int i = 0; i < cosine.length; i++) {
            double angle = -2.0 * Math.PI * i / WINDOW_SIZE;
            cosine[i] = Math.cos(angle);
            sine[i] = Math.sin(angle);
        }
        for (int i = 0; i <= BAND_COUNT; i++) {
            double hz = 20.0 * Math.pow(BAND_RATIO, i);
            bandStarts[i] = (int) Math.ceil(hz * WINDOW_SIZE / SAMPLE_RATE);
        }
    }

    void reset() {
        firstRetained = 0;
        nextFrame = 0;
    }

    void append(ByteBuffer pcm, int startByte, int writtenBytes, long firstFrame) {
        int frameCount = writtenBytes / 4;
        if (frameCount == 0) {
            return;
        }
        if (firstFrame != nextFrame) {
            firstRetained = firstFrame;
        }
        int skip = Math.max(0, frameCount - RETAINED_FRAMES);
        int offset = startByte + skip * 4;
        int ringIndex = (int) (firstFrame + skip) & RING_MASK;
        for (int i = skip; i < frameCount; i++) {
            left[ringIndex] = littleEndian(pcm, offset);
            right[ringIndex] = littleEndian(pcm, offset + 2);
            offset += 4;
            ringIndex = (ringIndex + 1) & RING_MASK;
        }
        nextFrame = firstFrame + frameCount;
        firstRetained = Math.max(firstRetained, nextFrame - RETAINED_FRAMES);
    }

    Sample sample(long consumedFrames) {
        long startFrame = consumedFrames - WINDOW_SIZE;
        if (startFrame < firstRetained || consumedFrames > nextFrame) {
            return null;
        }
        double sumSquares = 0.0;
        for (int i = 0; i < WINDOW_SIZE; i++) {
            int ringIndex = (int) (startFrame + i) & RING_MASK;
            double l = left[ringIndex] / 32768.0;
            double r = right[ringIndex] / 32768.0;
            sumSquares += l * l + r * r;
            int index = reverseIndex[i];
            real[index] = l * window[i];
            imaginary[index] = r * window[i];
        }

        transform();
        // The positive and negative frequencies of one complex transform
        // together hold the power of both real input channels.
        float[] bands = new float[BAND_COUNT];
        for (int band = 0; band < BAND_COUNT; band++) {
            double peak = 0.0;
            for (int bin = bandStarts[band]; bin < bandStarts[band + 1]; bin++) {
                int mirror = WINDOW_SIZE - bin;
                double power = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
                        + real[mirror] * real[mirror] + imaginary[mirror] * imaginary[mirror];
                peak = Math.max(peak, power);
            }
            bands[band] = (float) Math.min(1.0, Math.sqrt(peak) * windowScale);
        }
        float rms = (float) Math.sqrt(sumSquares / (2.0 * WINDOW_SIZE));
        return new Sample(bands, rms, consumedFrames);
    }

    private void transform() {
        for (int size = 2; size <= WINDOW_SIZE; size *= 2) {
            int half = size / 2;
            int stride = WINDOW_SIZE / size;
            for (int start = 0; start < WINDOW_SIZE; start += size) {
                for (int i = 0; i < half; i++) {
                    int first = start + i;
                    int second = first + half;
                    int phase = i * stride;
                    double productReal = real[second] * cosine[phase] - imaginary[second] * sine[phase];
                    double productImaginary = real[second] * sine[phase] + imaginary[second] * cosine[phase];
                    real[second] = real[first] - productReal;
                    imaginary[second] = imaginary[first] - productImaginary;
                    real[first] += productReal;
                    imaginary[first] += productImaginary;
                }
            }
        }
    }

    private static short littleEndian(ByteBuffer pcm, int offset) {
        return (short) ((pcm.get(offset) & 0xff) | (pcm.get(offset + 1) << 8));
    }
}
