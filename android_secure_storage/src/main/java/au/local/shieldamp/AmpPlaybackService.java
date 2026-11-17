package au.local.shieldamp;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.SystemClock;
import java.io.File;
import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Owns Android playback independently of Godot or an Activity's render surface. */
public final class AmpPlaybackService extends Service {
    private static final String CHANNEL = "kinegra-amp-playback";
    private static final int NOTICE = 1974;
    private static final String START = "start";
    private static final String COMMAND = "command";
    private static final String COMMAND_NAME = "command-name";
    private static final String COMMAND_VALUE = "command-value";
    private static final String STOP = "stop";
    private static final String PAUSE = "pause";
    private static final String RESUME = "resume";
    private static final String REQUEST_ID = "request";
    private static final int PAUSE_TIMEOUT_MS = 120000;
    private static final AtomicReference<Request> pending = new AtomicReference<>();
    private static final String IDLE = "{\"source\":\"none\",\"state\":\"idle\"}";
    private static volatile String snapshot = IDLE;
    private static volatile String localSnapshot = IDLE;
    private static volatile AmpPlaybackService activeInstance;
    private static volatile boolean activityAllowsPlayback = true;
    private static volatile int appGainPercent = 100;
    private static volatile boolean activityVisible = true;
    private static volatile boolean analysisRequested;
    private static volatile Analysis latestAnalysis;

    private static final class Analysis {
        final long generation;
        final long presentedAtNs;
        final SendspinSpectrum.Sample window;

        final double playbackMs;

        Analysis(long generation, long presentedAtNs, SendspinSpectrum.Sample window, double playbackMs) {
            this.generation = generation;
            this.presentedAtNs = presentedAtNs;
            this.window = window;
            this.playbackMs = playbackMs;
        }
    }

    static void setActivityVisible(boolean visible) {
        activityVisible = visible;
        if (!visible) latestAnalysis = null;
    }

    static void setAnalysisRequested(boolean enabled) {
        analysisRequested = enabled;
        if (!enabled) latestAnalysis = null;
    }

    static String analysisSnapshot() {
        Analysis current = latestAnalysis;
        if (!activityVisible || !analysisRequested || current == null) return "";
        long ageNs = System.nanoTime() - current.presentedAtNs;
        if (ageNs < 0 || ageNs > 500_000_000L) return "";
        try {
            JSONArray bands = new JSONArray();
            for (float band : current.window.bands) bands.put((double) band);
            JSONObject sample = new JSONObject();
            sample.put("generation", current.generation);
            sample.put("age_ms", ageNs / 1000000L);
            sample.put("playback_ms", current.playbackMs);
            sample.put("rms", (double) current.window.rms);
            sample.put("bands", bands);
            return sample.toString();
        } catch (JSONException invalid) {
            return "";
        }
    }

    static boolean setAppGainPercent(int percent) {
        if (percent < 0 || percent > 100) return false;
        appGainPercent = percent;
        AmpPlaybackService current = activeInstance;
        if (current != null) current.owner.post(current::applyAppGain);
        return true;
    }

    static void setActivityPlaybackAllowed(boolean allowed) {
        activityAllowsPlayback = allowed;
        AmpPlaybackService current = activeInstance;
        if (!allowed && current != null) {
            current.owner.post(() -> {
                if (!activityAllowsPlayback && current.focused) current.pausePlayback();
            });
        }
    }

    private static final class Request {
        final String id = UUID.randomUUID().toString();
        final String endpoint;

        final LocalFileQueue.Plan local;

        Request(String endpoint, LocalFileQueue.Plan local) {
            this.endpoint = endpoint;
            this.local = local;
        }
    }

    /** Called from the visible Activity to open the verified Music Assistant endpoint. */
    static boolean connectSendspin(Context context, String endpoint) {
        if (endpoint == null || endpoint.length() < 10 || endpoint.length() > 512)
            return false;
        return start(context, new Request(endpoint, null));
    }

    static boolean playLocal(Context context, String raw) {
        LocalFileQueue.Plan plan = LocalFileQueue.Plan.parse(raw);
        return plan != null && start(context, new Request(null, plan));
    }

    static String localPlaybackSnapshot() { return localSnapshot; }

    static boolean updateLocalQueue(String raw) {
        LocalFileQueue.Plan plan = LocalFileQueue.Plan.parse(raw);
        AmpPlaybackService service = activeInstance;
        if (plan == null || service == null) return false;
        return service.owner.post(() -> {
            if (!service.destroyed && service.local != null) service.local.update(plan);
        });
    }

    static boolean localCommand(int token, String command, int argument) {
        if ("stop".equals(command)) {
            Request request = pending.get();
            if (request != null && request.local != null && request.local.token == token) {
                pending.compareAndSet(request, null);
            }
        }
        AmpPlaybackService service = activeInstance;
        if (service == null) return false;
        return service.owner.post(() -> {
            LocalFileQueue current = service.local;
            if (!service.destroyed && current != null && current.token() == token) {
                service.dispatch(command, argument);
                if (service.local == current) service.publishLocal();
            }
        });
    }

    private static boolean start(Context context, Request request) {
        pending.set(request);
        try {
            context.startForegroundService(new Intent(context, AmpPlaybackService.class)
                    .setAction(START).putExtra(REQUEST_ID, request.id));
            return true;
        } catch (RuntimeException unavailable) {
            pending.compareAndSet(request, null);
            return false;
        }
    }

    static String playbackSnapshot() { return snapshot; }

    static boolean command(Context context, String command, int argument) {
        if (snapshot.equals(IDLE) || snapshot.contains("\"source\":\"local\"")) return false;
        try {
            context.startService(new Intent(context, AmpPlaybackService.class).setAction(COMMAND)
                    .putExtra(COMMAND_NAME, command).putExtra(COMMAND_VALUE, argument));
            return true;
        } catch (RuntimeException unavailable) {
            return false;
        }
    }

    private HandlerThread worker;
    private Handler owner;
    private AudioManager audio;
    private AudioFocusRequest focus;
    private MediaSession mediaSession;
    private NativeSendspinWorker sendspin;
    private LocalFileQueue local;
    private int localToken;
    private long lastLocalPublication;
    private final Runnable localTick = this::runLocalTick;
    private long sendspinOpened;
    private long lastSendspinPublication;
    private long lastAnalysisPublication;
    private final Runnable sendspinTick = this::runSendspinTick;
    private String previousMode = "";
    private PendingIntent openApp;
    private int activeStartId;
    private boolean focused;
    private volatile boolean destroyed;
    private boolean established;
    private final Runnable pauseTimeout = this::stopPlayback;

    @Override public void onCreate() {
        super.onCreate();
        worker = new HandlerThread("AmpPlaybackOwner");
        worker.start();
        owner = new Handler(worker.getLooper());
        activeInstance = this;
        audio = getSystemService(AudioManager.class);
        focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setOnAudioFocusChangeListener(this::focusChanged, owner)
                .setWillPauseWhenDucked(true).build();
        getSystemService(NotificationManager.class).createNotificationChannel(
                new NotificationChannel(CHANNEL, "Music playback", NotificationManager.IMPORTANCE_LOW));
        Intent launch = getPackageManager().getLeanbackLaunchIntentForPackage(getPackageName());
        if (launch != null) {
            openApp = PendingIntent.getActivity(this, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        }
        mediaSession = new MediaSession(this, "KinegraAmp");
        mediaSession.setSessionActivity(openApp);
        mediaSession.setCallback(new MediaSession.Callback() {
            @Override public void onPlay() { resumePlayback(); }
            @Override public void onPause() { pausePlayback(); }
            @Override public void onStop() { stopPlayback(); }
            @Override public void onSeekTo(long at) {
                if (at >= 0 && at <= Integer.MAX_VALUE) dispatch("seek", (int) at);
            }
            @Override public void onSkipToNext() { dispatch("next", -1); }
            @Override public void onSkipToPrevious() { dispatch("previous", -1); }
        }, owner);
    }

    @Override public IBinder onBind(Intent intent) { return null; }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? "" : intent.getAction();
        if (START.equals(action)) {
            // Android times foreground promotion from startForegroundService,
            // not from audio preparation or initial audio-focus acquisition.
            try {
                if (Build.VERSION.SDK_INT >= 29) {
                    startForeground(NOTICE, notification(false), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
                } else {
                    startForeground(NOTICE, notification(false));
                }
            } catch (RuntimeException unavailable) {
                stopSelfResult(startId);
                return START_NOT_STICKY;
            }
            Request request = pending.get();
            if (request != null && request.id.equals(intent.getStringExtra(REQUEST_ID))
                    && pending.compareAndSet(request, null)) {
                owner.post(() -> {
                    if (request.local == null) startSendspin(request.endpoint, startId);
                    else startLocal(request.local, startId);
                });
            } else {
                owner.post(() -> {
                    if (!hasSource() && pending.get() == null) stopSelfResult(startId);
                });
            }
        } else {
            owner.post(() -> {
                activeStartId = startId;
                if (destroyed || !hasSource() || STOP.equals(action)) stopPlayback();
                else if (PAUSE.equals(action)) pausePlayback();
                else if (RESUME.equals(action)) resumePlayback();
                else if (COMMAND.equals(action) && intent != null && sendspin != null)
                    dispatch(intent.getStringExtra(COMMAND_NAME), intent.getIntExtra(COMMAND_VALUE, -1));
            });
        }
        return START_NOT_STICKY;
    }

    private boolean hasSource() { return sendspin != null || local != null; }

    private void startLocal(LocalFileQueue.Plan plan, int startId) {
        if (destroyed) return;
        activeStartId = startId;
        clearSource();
        localToken = plan.token;
        lastLocalPublication = lastAnalysisPublication = 0;
        try {
            File directory = new File(getFilesDir().getCanonicalFile(), "offline_music");
            local = new LocalFileQueue(directory, plan, appGainPercent);
            established = true;
            mediaSession.setActive(true);
            resumePlayback();
            runLocalTick();
        } catch (IOException | RuntimeException unavailable) {
            failLocal();
        }
    }

    private void runLocalTick() {
        if (destroyed || local == null) return;
        try {
            boolean analyze = activityVisible && analysisRequested;
            local.tick(analyze);
            long now = SystemClock.elapsedRealtime();
            if (latestAnalysis != null && (!analyze || latestAnalysis.generation != local.currentGeneration()))
                latestAnalysis = null;
            if (analyze && now - lastAnalysisPublication >= 50) {
                SendspinSpectrum.Sample window = local.analysisSample();
                latestAnalysis = window == null ? null :
                        new Analysis(local.currentGeneration(), local.analysisTimeNs(), window, local.positionMs());
                lastAnalysisPublication = now;
            }
            if (now - lastLocalPublication >= 250 || !local.active()) {
                publishLocal();
                lastLocalPublication = now;
            }
            if (!local.active()) {
                clearSource();
                stopSelfResult(activeStartId);
                return;
            }
            owner.postDelayed(localTick, focused ? 10 : 100);
        } catch (IOException | RuntimeException unavailable) {
            failLocal();
        }
    }

    private void publishLocal() {
        if (local == null) return;
        try {
            JSONObject current = local.snapshot();
            localSnapshot = current.toString();
            publish(current);
        } catch (JSONException invalid) {
            throw new IllegalStateException("Could not describe offline playback", invalid);
        }
    }

    private void failLocal() {
        if (local != null) {
            local.fail();
            publishLocal();
        } else {
            localSnapshot = "{\"source\":\"local\",\"state\":\"error\",\"token\":" + localToken + "}";
        }
        clearSource();
        stopSelfResult(activeStartId);
    }

    private void startSendspin(String endpoint, int startId) {
        if (destroyed) return;
        activeStartId = startId;
        clearSource();
        try {
            sendspin = new NativeSendspinWorker(this);
            sendspin.setAppGainPercent(appGainPercent);
            if (!sendspin.open(endpoint)) {
                failSendspin("Music Assistant player connection unavailable");
                return;
            }
            established = true;
            sendspinOpened = SystemClock.elapsedRealtime();
            lastSendspinPublication = 0;
            lastAnalysisPublication = 0;
            mediaSession.setActive(true);
            runSendspinTick();
        } catch (LinkageError | RuntimeException failure) {
            failSendspin("Music Assistant audio unavailable");
        }
    }

    private void runSendspinTick() {
        if (destroyed || sendspin == null) return;
        try {
            final boolean analyze = activityVisible && analysisRequested;
            sendspin.setAnalysisEnabled(analyze);
            if (!sendspin.tick()) {
                failSendspin("Music Assistant audio stopped");
                return;
            }
            long now = SystemClock.elapsedRealtime();
            if (latestAnalysis != null && (!analyze || latestAnalysis.generation != sendspin.currentGeneration()))
                latestAnalysis = null;
            if (analyze && now - lastAnalysisPublication >= 50) {
                SendspinSpectrum.Sample window = sendspin.analysisSample();
                latestAnalysis = window == null ? null :
                        new Analysis(sendspin.currentGeneration(), sendspin.reportedAtNs(), window, window.frame * 1000.0 / 48000);
                lastAnalysisPublication = now;
            }
            if (now - lastSendspinPublication >= 250) {
                JSONObject current = sendspin.snapshot();
                if (!current.optBoolean("paired") && now - sendspinOpened > 120000) {
                    failSendspin("Music Assistant pairing timed out");
                    return;
                }
                lastSendspinPublication = now;
                publish(current);
            }
            owner.postDelayed(sendspinTick, 10);
        } catch (RuntimeException unavailable) {
            failSendspin("Music Assistant audio unavailable");
        }
    }

    private void failSendspin(String error) {
        clearSource();
        JSONObject state = new JSONObject();
        try {
            state.put("source", "ma");
            state.put("state", "error");
            state.put("error", error);
        } catch (JSONException impossible) {
            throw new IllegalStateException(impossible);
        }
        snapshot = state.toString();
        stopSelfResult(activeStartId);
    }

    private void dispatch(String action, int argument) {
        if (destroyed || !hasSource() || action == null) return;
        if (local != null) {
            try {
                switch (action) {
                    case "play": resumePlayback(); break;
                    case "pause": pausePlayback(); break;
                    case "stop": stopPlayback(); break;
                    case "seek": local.seek(argument); break;
                    case "next": case "previous":
                        if (obtainFocus()) {
                            local.play();
                            local.navigate("next".equals(action) ? 1 : -1, false);
                        }
                        break;
                    default: break;
                }
                latestAnalysis = null;
            } catch (IOException | RuntimeException unavailable) {
                failLocal();
            }
            return;
        }
        switch (action) {
            case "play": resumePlayback(); break;
            case "pause": pausePlayback(); break;
            case "stop": stopPlayback(); break;
            case "seek":
                if (argument >= 0) sendspin.command(action, argument);
                break;
            case "previous":
            case "next":
                sendspin.command(action, -1);
                break;
            case "confirm":
                sendspin.confirm();
                break;
            case "permit":
                if (sendspin.trusted() && obtainFocus()) {
                    owner.removeCallbacks(pauseTimeout);
                    sendspin.permitPlayback(true);
                }
                break;
            default:
                break;
        }
    }

    private void applyAppGain() {
        if (destroyed) return;
        if (local != null) {
            try { local.setGain(appGainPercent); }
            catch (RuntimeException unavailable) { failLocal(); }
            return;
        }
        if (sendspin == null) return;
        try {
            sendspin.setAppGainPercent(appGainPercent);
        } catch (RuntimeException unavailable) {
            failSendspin("Could not apply Kinegra Amp volume");
        }
    }

    private boolean obtainFocus() {
        if (!activityAllowsPlayback) return false;
        if (!focused) focused = audio.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
        return focused;
    }

    private void resumePlayback() {
        if (destroyed || !hasSource() || !established) return;
        boolean hadFocus = focused;
        if (!obtainFocus()) return;
        if (local != null) {
            try {
                if (!local.play() && !hadFocus) releaseFocus();
            } catch (RuntimeException unavailable) {
                failLocal();
            }
            return;
        }
        if (sendspin.command("play", -1)) {
            owner.removeCallbacks(pauseTimeout);
            sendspin.permitPlayback(true);
        } else if (!hadFocus) {
            releaseFocus();
        }
    }

    private void pausePlayback() {
        if (destroyed || !hasSource()) return;
        if (local != null) {
            try { local.pause(); }
            catch (RuntimeException unavailable) { failLocal(); return; }
            latestAnalysis = null;
            releaseFocus();
            publishLocal();
            return;
        }
        sendspin.permitPlayback(false);
        sendspin.command("pause", -1);
        latestAnalysis = null;
        releaseFocus();
        owner.removeCallbacks(pauseTimeout);
        owner.postDelayed(pauseTimeout, PAUSE_TIMEOUT_MS);
    }

    private void stopPlayback() {
        if (local != null) {
            local.stop();
            publishLocal();
        }
        if (sendspin != null) {
            sendspin.permitPlayback(false);
            sendspin.command("stop", -1);
        }
        clearSource();
        stopSelfResult(activeStartId);
    }

    private void clearSource() {
        owner.removeCallbacks(pauseTimeout);
        owner.removeCallbacks(sendspinTick);
        owner.removeCallbacks(localTick);
        LocalFileQueue offline = local;
        local = null;
        if (offline != null) offline.close();
        previousMode = "";
        established = false;
        snapshot = IDLE;
        latestAnalysis = null;
        NativeSendspinWorker player = sendspin;
        sendspin = null;
        if (player != null) player.close();
        releaseFocus();
    }

    private void releaseFocus() {
        if (!focused) return;
        focused = false;
        audio.abandonAudioFocusRequest(focus);
    }

    private void focusChanged(int state) {
        if (destroyed || !focused) return;
        if (state == AudioManager.AUDIOFOCUS_LOSS) stopPlayback();
        else if (state == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ||
                 state == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) pausePlayback();
    }

    private void publish(JSONObject state) {
        if (destroyed) return;
        snapshot = state.toString();
        String mode = state.optString("state");
        boolean playing = "playing".equals(mode);
        boolean buffering = "buffering".equals(mode) || "connecting".equals(mode);
        long actions = PlaybackState.ACTION_STOP;
        if (state.optBoolean("can_play")) actions |= PlaybackState.ACTION_PLAY;
        if (state.optBoolean("can_pause")) actions |= PlaybackState.ACTION_PAUSE;
        if (state.optBoolean("can_play") && state.optBoolean("can_pause"))
            actions |= PlaybackState.ACTION_PLAY_PAUSE;
        if (state.optBoolean("can_seek")) actions |= PlaybackState.ACTION_SEEK_TO;
        if (state.optBoolean("can_next")) actions |= PlaybackState.ACTION_SKIP_TO_NEXT;
        if (state.optBoolean("can_previous")) actions |= PlaybackState.ACTION_SKIP_TO_PREVIOUS;
        if (previousMode.isEmpty()) {
            mediaSession.setMetadata(new MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, local == null ? "Music Assistant" : "Offline Library").build());
        }
        mediaSession.setPlaybackState(new PlaybackState.Builder()
                .setActions(actions)
                .setState(playing ? PlaybackState.STATE_PLAYING :
                        (buffering ? PlaybackState.STATE_BUFFERING : PlaybackState.STATE_PAUSED),
                        state.optInt("position_ms"), playing ? 1.0f : 0.0f).build());
        if (!previousMode.equals(mode)) {
            getSystemService(NotificationManager.class).notify(NOTICE, notification(playing));
        }
        previousMode = mode;
    }

    private Notification notification(boolean playing) {
        int icon = playing ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play;
        Notification.Builder builder = new Notification.Builder(this, CHANNEL)
                .setContentTitle("Kinegra Amp")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setOngoing(playing)
                .addAction(new Notification.Action.Builder(icon, playing ? "Pause" : "Play",
                        action(playing ? PAUSE : RESUME, 1)).build())
                .addAction(new Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel,
                        "Stop", action(STOP, 2)).build())
                .setStyle(new Notification.MediaStyle().setMediaSession(mediaSession.getSessionToken())
                        .setShowActionsInCompactView(0, 1));
        if (openApp != null) builder.setContentIntent(openApp);
        return builder.build();
    }

    private PendingIntent action(String command, int request) {
        return PendingIntent.getService(this, request,
                new Intent(this, AmpPlaybackService.class).setAction(command),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    @Override public void onDestroy() {
        destroyed = true;
        if (activeInstance == this) activeInstance = null;
        owner.post(() -> {
            if (hasSource()) clearSource();
            mediaSession.release();
            worker.quitSafely();
        });
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
}
