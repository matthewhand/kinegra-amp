package au.local.shieldamp;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTimestamp;
import android.media.AudioTrack;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;

/** Decodes one app-owned file and feeds its actual PCM to Android and the optional foreground spectrum. */
final class LocalFileOutput implements AutoCloseable {
    private final MediaExtractor extractor = new MediaExtractor();
    private final MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
    private final AudioTimestamp timestamp = new AudioTimestamp();
    private MediaCodec codec;
    private AudioTrack track;
    private SendspinSpectrum spectrum;
    private int outputIndex = -1;
    private ByteBuffer pending;
    private int rate, frameBytes;
    private int gain;
    private int originMs;
    private boolean inputEnded, outputEnded, running, analyze, started;
    private long submitted, presented;
    private long presentedAtNs, lastAdvanceNs;
    final int durationMs;

    LocalFileOutput(File file, int atMs, int gain) throws IOException {
        this.gain = gain;
        originMs = atMs;
        try {
            extractor.setDataSource(file.getPath());
            MediaFormat format = selectAudio();
            if (format.containsKey(MediaFormat.KEY_DURATION)) {
                durationMs = (int) Math.max(0, Math.min(Integer.MAX_VALUE,
                        format.getLong(MediaFormat.KEY_DURATION) / 1000));
            } else durationMs = 0;
            if (atMs > 0) extractor.seekTo(atMs * 1000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC);
            format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT);
            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));
            codec.configure(format, null, null, 0);
            codec.start();
        } catch (IOException | RuntimeException unavailable) {
            close();
            throw unavailable;
        }
    }

    private MediaFormat selectAudio() throws IOException {
        for (int index = 0; index < extractor.getTrackCount(); index++) {
            MediaFormat format = extractor.getTrackFormat(index);
            String type = format.getString(MediaFormat.KEY_MIME);
            if ("audio/mpeg".equals(type) || "audio/vorbis".equals(type)) {
                extractor.selectTrack(index);
                return format;
            }
        }
        throw new IOException("Unsupported offline audio format");
    }

    void play() {
        running = true;
        lastAdvanceNs = System.nanoTime();
        if (started && track != null) track.play();
    }

    void pause() {
        running = false;
        if (started && track != null) {
            track.pause();
            readCursor();
        }
        spectrum = null;
    }

    void setGain(int percent) {
        gain = percent;
        if (track != null && track.setVolume(gain / 100f) != AudioTrack.SUCCESS) {
            throw new IllegalStateException("Offline audio gain unavailable");
        }
    }

    void setAnalysisEnabled(boolean enabled) {
        if (enabled == analyze) return;
        analyze = enabled;
        if (!enabled) spectrum = null;
    }

    boolean tick() {
        if (!running) return false;
        if (track != null) readCursor();
        if (System.nanoTime() - lastAdvanceNs > 5_000_000_000L)
            throw new IllegalStateException("Offline audio output stalled");
        for (int attempt = 0; attempt < 8; attempt++) {
            feed();
            if (pending == null && !outputEnded) takeOutput();
            if (pending == null) break;
            writePending();
            if (pending != null) break;
        }
        if (!started && track != null && submitted > 0 &&
                (submitted >= Math.min(rate / 10, track.getBufferSizeInFrames()) || outputEnded)) {
            track.play();
            started = true;
        }
        if (!outputEnded || pending != null) return false;
        if (submitted == 0) throw new IllegalStateException("Offline file produced no audio");
        return presented >= submitted;
    }

    private void feed() {
        if (inputEnded) return;
        int index = codec.dequeueInputBuffer(0);
        if (index < 0) return;
        ByteBuffer input = codec.getInputBuffer(index);
        if (input == null) throw new IllegalStateException("Offline decoder input missing");
        input.clear();
        int length = extractor.readSampleData(input, 0);
        if (length < 0) {
            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
            inputEnded = true;
        } else {
            codec.queueInputBuffer(index, 0, length, extractor.getSampleTime(), 0);
            extractor.advance();
        }
    }

    private void takeOutput() {
        int index = codec.dequeueOutputBuffer(info, 0);
        if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
            configureTrack(codec.getOutputFormat());
            return;
        }
        if (index < 0) return;
        outputIndex = index;
        outputEnded = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
        if (info.size == 0 || (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
            releaseOutput();
            return;
        }
        if (track == null) configureTrack(codec.getOutputFormat());
        if (info.size % frameBytes != 0) throw new IllegalStateException("Incomplete offline PCM frame");
        pending = codec.getOutputBuffer(index);
        if (pending == null) throw new IllegalStateException("Offline decoder output missing");
        pending.limit(info.offset + info.size);
        pending.position(info.offset);
        if (submitted == 0) {
            long skip = Math.max(0, (originMs * 1000L - info.presentationTimeUs) * rate / 1000000L);
            if (skip >= pending.remaining() / frameBytes) {
                releaseOutput();
                return;
            }
            pending.position(info.offset + (int) skip * frameBytes);
            long firstUs = info.presentationTimeUs + skip * 1000000L / rate;
            originMs = (int) Math.max(0, Math.min(Integer.MAX_VALUE, firstUs / 1000L));
        }
    }

    private void configureTrack(MediaFormat format) {
        int sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
        int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
        int encoding = format.containsKey(MediaFormat.KEY_PCM_ENCODING)
                ? format.getInteger(MediaFormat.KEY_PCM_ENCODING) : AudioFormat.ENCODING_PCM_16BIT;
        if (sampleRate < 8000 || sampleRate > 192000 || (channels != 1 && channels != 2)
                || encoding != AudioFormat.ENCODING_PCM_16BIT) {
            throw new IllegalStateException("Offline PCM format unsupported");
        }
        if (track != null) {
            if (sampleRate != rate || channels * 2 != frameBytes) {
                throw new IllegalStateException("Offline PCM output changed format");
            }
            return;
        }
        rate = sampleRate;
        frameBytes = channels * 2;
        int mask = channels == 1 ? AudioFormat.CHANNEL_OUT_MONO : AudioFormat.CHANNEL_OUT_STEREO;
        int minimum = AudioTrack.getMinBufferSize(rate, mask, encoding);
        if (minimum <= 0) throw new IllegalStateException("Offline output format unavailable");
        int bufferBytes = Math.max(minimum, rate * frameBytes / 4);
        track = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioFormat(new AudioFormat.Builder().setSampleRate(rate)
                        .setChannelMask(mask).setEncoding(encoding).build())
                .setBufferSizeInBytes(bufferBytes).setTransferMode(AudioTrack.MODE_STREAM).build();
        if (track.getState() != AudioTrack.STATE_INITIALIZED) throw new IllegalStateException("Offline player unavailable");
        setGain(gain);
    }

    private void writePending() {
        int offset = pending.position();
        int amount = track.write(pending, pending.remaining(), AudioTrack.WRITE_NON_BLOCKING);
        if (amount < 0 || amount % frameBytes != 0) throw new IllegalStateException("Offline audio write failed");
        if (amount > 0) {
            if (analyze && spectrum == null) spectrum = new SendspinSpectrum(rate, frameBytes / 2);
            if (spectrum != null) spectrum.append(pending, offset, amount, submitted);
            submitted += amount / frameBytes;
        }
        if (!pending.hasRemaining()) releaseOutput();
    }

    private void releaseOutput() {
        codec.releaseOutputBuffer(outputIndex, false);
        outputIndex = -1;
        pending = null;
    }

    private void readCursor() {
        long lower = Integer.toUnsignedLong(track.getPlaybackHeadPosition());
        long extended = (presented & ~0xffffffffL) | lower;
        if (extended + 0x80000000L < presented) extended += 0x100000000L;
        if (extended > presented && extended <= submitted) {
            presented = extended;
            lastAdvanceNs = System.nanoTime();
        }
    }

    boolean presenting() { return running && started && presented > 0; }

    int positionMs() {
        if (rate == 0) return originMs;
        long estimate = originMs + presented * 1000 / rate;
        return (int) Math.min(durationMs > 0 ? durationMs : Integer.MAX_VALUE, estimate);
    }

    SendspinSpectrum.Sample analysisSample() {
        if (spectrum == null || !presenting() || !track.getTimestamp(timestamp)) return null;
        presentedAtNs = timestamp.nanoTime;
        long lower = timestamp.framePosition & 0xffffffffL;
        long frame = (presented & ~0xffffffffL) | lower;
        if (frame > presented + 0x80000000L) frame -= 0x100000000L;
        if (frame + 0x80000000L < presented) frame += 0x100000000L;
        return spectrum.sample(frame);
    }

    long presentedAtNs() { return presentedAtNs; }

    @Override public void close() {
        if (track != null) {
            track.release();
            track = null;
        }
        if (codec != null) {
            codec.release();
            codec = null;
        }
        extractor.release();
        pending = null;
        spectrum = null;
    }
}
