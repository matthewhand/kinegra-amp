package au.local.shieldamp;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Queue and cursor for the Android-owned offline file player. All calls run on the service thread. */
final class LocalFileQueue implements AutoCloseable {
    private static final Pattern FILENAME = Pattern.compile("import_[0-9a-f]{64}\\.(mp3|ogg)");
    private static final int MAX_FILES = 4096;
    private static final int MAX_QUEUE = 8192;
    private static final long MAX_BYTES = 64L * 1024 * 1024;

    private static final class Entry {
        final int occurrence, id;
        Entry(int occurrence, int id) {
            this.occurrence = occurrence;
            this.id = id;
        }
    }

    static final class Plan {
        final int token, selected, selectedOccurrence;
        final Map<Integer, String> files = new HashMap<>();
        final List<Entry> queue = new ArrayList<>();
        final List<Integer> order = new ArrayList<>();
        final String repeat;
        final boolean shuffle;

        private Plan(JSONObject data) throws JSONException {
            token = data.getInt("token");
            selected = data.getInt("selected");
            selectedOccurrence = data.getInt("selected_occurrence");
            repeat = data.getString("repeat");
            shuffle = data.getBoolean("shuffle");
            if (token <= 0 || selectedOccurrence < 0 || !("ALL".equals(repeat) || "ONE".equals(repeat) || "OFF".equals(repeat))) {
                throw new JSONException("Invalid local playback plan");
            }
            JSONArray catalog = data.getJSONArray("files");
            JSONArray upcoming = data.getJSONArray("queue");
            JSONArray playlist = data.getJSONArray("order");
            if (catalog.length() == 0 || catalog.length() > MAX_FILES || playlist.length() > MAX_FILES || upcoming.length() > MAX_QUEUE) {
                throw new JSONException("Local playback plan exceeds limits");
            }
            for (int i = 0; i < catalog.length(); i++) {
                JSONArray file = catalog.getJSONArray(i);
                int id = file.getInt(0);
                String name = file.getString(1);
                if (id < 4 || id >= MAX_FILES + 4 || !FILENAME.matcher(name).matches() ||
                        files.put(id, name) != null) throw new JSONException("Invalid local file");
            }
            Set<Integer> seen = new HashSet<>();
            for (int i = 0; i < upcoming.length(); i++) {
                JSONArray entry = upcoming.getJSONArray(i);
                int occurrence = entry.getInt(0);
                int id = entry.getInt(1);
                if (occurrence <= 0 || !seen.add(occurrence) || !files.containsKey(id)) {
                    throw new JSONException("Invalid local queue entry");
                }
                queue.add(new Entry(occurrence, id));
            }
            seen.clear();
            for (int i = 0; i < playlist.length(); i++) {
                int id = playlist.getInt(i);
                if (!seen.add(id) || !files.containsKey(id)) throw new JSONException("Invalid local playlist");
                order.add(id);
            }
            if (!files.containsKey(selected)) throw new JSONException("Invalid selected local file");
        }

        static Plan parse(String raw) {
            if (raw == null || raw.length() > 750000) return null;
            try { return new Plan(new JSONObject(raw)); }
            catch (JSONException invalid) { return null; }
        }
    }

    private final File directory;
    private final Set<Integer> consumed = new HashSet<>();
    private Plan plan;
    private LocalFileOutput output;
    private int current, pendingOccurrence, gain, generation;
    private boolean running;
    private String terminal = "";

    LocalFileQueue(File directory, Plan plan, int gain) throws IOException {
        this.directory = directory.getCanonicalFile();
        if (!directory.equals(this.directory) || !directory.isDirectory()) throw new IOException("Offline library unavailable");
        this.plan = plan;
        this.gain = gain;
        open(plan.selected, plan.selectedOccurrence, 0);
    }

    private void open(int id, int occurrence, int positionMs) throws IOException {
        closeOutput();
        String name = plan.files.get(id);
        if (name == null) throw new IOException("Offline file unavailable");
        File candidate = new File(directory, name);
        long size = candidate.length();
        if (!candidate.equals(candidate.getCanonicalFile()) || !candidate.isFile() ||
                size < 4 || size > MAX_BYTES) throw new IOException("Invalid offline file");
        output = new LocalFileOutput(candidate, positionMs, gain);
        generation++;
        current = id;
        pendingOccurrence = occurrence;
        if (running) output.play();
    }

    int token() { return plan.token; }
    int currentGeneration() { return generation; }

    void update(Plan updated) {
        if (updated.token != plan.token || !updated.files.containsKey(current)) return;
        Set<Integer> retained = new HashSet<>();
        for (Entry entry : updated.queue) retained.add(entry.occurrence);
        consumed.retainAll(retained);
        plan = updated;
    }

    boolean play() {
        if (output == null) return false;
        running = true;
        output.play();
        return true;
    }

    void pause() {
        running = false;
        if (output != null) output.pause();
    }

    void stop() {
        running = false;
        terminal = "stopped";
        closeOutput();
    }

    void fail() {
        stop();
        terminal = "error";
    }

    void seek(int at) throws IOException {
        if (output == null || at < 0) return;
        int duration = output.durationMs;
        open(current, pendingOccurrence, duration > 0 ? Math.min(duration - 1, at) : at);
    }

    void setGain(int percent) {
        gain = percent;
        if (output != null) output.setGain(percent);
    }

    void navigate(int direction, boolean automatic) throws IOException {
        if (output == null) return;
        if (direction > 0) {
            for (Entry entry : plan.queue) {
                if (!consumed.contains(entry.occurrence) && entry.occurrence != pendingOccurrence) {
                    open(entry.id, entry.occurrence, 0);
                    return;
                }
            }
            if (automatic && "ONE".equals(plan.repeat)) {
                open(current, 0, 0);
                return;
            }
        }
        int index = plan.order.indexOf(current);
        int size = plan.order.size();
        if (size == 0 || (automatic && "OFF".equals(plan.repeat) && index == size - 1)) {
            if (automatic) stop();
            return;
        }
        if (index < 0) index = direction > 0 ? -1 : 0;
        int next = index + direction;
        if (plan.shuffle && direction < 0 && next < 0) next = 0;
        if (plan.shuffle && next >= size && size > 1) {
            ArrayList<Integer> reshuffled = new ArrayList<>(plan.order);
            reshuffled.remove((Integer) current);
            Collections.shuffle(reshuffled);
            reshuffled.add(0, current);
            plan.order.clear();
            plan.order.addAll(reshuffled);
            next = 1;
        }
        open(plan.order.get(Math.floorMod(next, size)), 0, 0);
    }

    void tick(boolean analyze) throws IOException {
        if (output == null) return;
        output.setAnalysisEnabled(analyze);
        boolean ended = output.tick();
        if (pendingOccurrence > 0 && output.presenting()) {
            consumed.add(pendingOccurrence);
            pendingOccurrence = 0;
        }
        if (ended) navigate(1, true);
    }

    SendspinSpectrum.Sample analysisSample() { return output == null ? null : output.analysisSample(); }
    long analysisTimeNs() { return output == null ? 0 : output.presentedAtNs(); }
    int positionMs() { return output == null ? 0 : output.positionMs(); }
    boolean active() { return output != null; }

    JSONObject snapshot() throws JSONException {
        String mode = output == null ? terminal : (running ? (output.presenting() ? "playing" : "buffering") : "paused");
        return new JSONObject()
                .put("source", "local").put("state", mode).put("token", plan.token)
                .put("generation", generation).put("track", current)
                .put("position_ms", positionMs()).put("duration_ms", output == null ? 0 : output.durationMs)
                .put("consumed", new JSONArray(consumed))
                .put("can_play", active()).put("can_pause", active()).put("can_seek", active())
                .put("can_next", active()).put("can_previous", active());
    }

    private void closeOutput() {
        if (output != null) {
            output.close();
            output = null;
        }
    }

    @Override public void close() { closeOutput(); }
}
