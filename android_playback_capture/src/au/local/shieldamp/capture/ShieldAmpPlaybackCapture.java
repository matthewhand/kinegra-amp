package au.local.shieldamp.capture;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import java.util.concurrent.atomic.AtomicInteger;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/** Unshipped opt-in Godot bridge: no operation happens before startCapture(). */
public final class ShieldAmpPlaybackCapture extends GodotPlugin {
    private static final int PERMISSION_REQUEST = 27381, PROJECTION_REQUEST = 27382;
    private volatile boolean pending;
    private volatile boolean dialogInFlight;
    private final AtomicInteger generation = new AtomicInteger();
    public ShieldAmpPlaybackCapture(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "ShieldAmpPlaybackCapture"; }

    @UsedByGodot public void startCapture() {
        final Activity activity = getActivity();
        if (activity == null || Build.VERSION.SDK_INT < 29) { CaptureService.state = "unavailable"; return; }
        final int requestGeneration = generation.get();
        runOnUiThread(() -> {
            if (requestGeneration != generation.get()) return;
            if (pending || dialogInFlight || CaptureService.session != null || "starting".equals(CaptureService.state)) return;
            pending = true;
            if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                CaptureService.state = "awaiting_audio_permission";
                try {
                    dialogInFlight = true;
                    activity.requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, PERMISSION_REQUEST);
                } catch (RuntimeException failure) {
                    dialogInFlight = false; pending = false; CaptureService.state = "unavailable";
                }
            } else requestProjection(activity);
        });
    }
    private void requestProjection(Activity activity) {
        try {
            MediaProjectionManager manager = (MediaProjectionManager) activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE);
            if (manager == null) throw new IllegalStateException("projection unavailable");
            CaptureService.state = "awaiting_projection_consent";
            dialogInFlight = true;
            activity.startActivityForResult(manager.createScreenCaptureIntent(), PROJECTION_REQUEST);
        } catch (RuntimeException failure) { dialogInFlight = false; pending = false; CaptureService.state = "unavailable"; }
    }
    @Override public void onMainRequestPermissionsResult(int code, String[] permissions, int[] grants) {
        if (code != PERMISSION_REQUEST) return;
        dialogInFlight = false;
        if (!pending) return;
        Activity activity = getActivity();
        if (activity == null || grants.length == 0 || grants[0] != PackageManager.PERMISSION_GRANTED) {
            pending = false; CaptureService.state = "permission_denied"; return;
        }
        requestProjection(activity);
    }
    @Override public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != PROJECTION_REQUEST) return;
        dialogInFlight = false;
        if (!pending) return;
        pending = false;
        Activity activity = getActivity();
        if (activity == null || resultCode != Activity.RESULT_OK || data == null) { CaptureService.state = "consent_denied"; return; }
        Intent intent = new Intent(activity, CaptureService.class).setAction(CaptureService.START)
                .putExtra("result_code", resultCode).putExtra("result_data", data);
        try { CaptureService.state = "starting"; activity.startForegroundService(intent); }
        catch (RuntimeException failure) { CaptureService.state = "start_error"; }
    }
    @UsedByGodot public void stopCapture() {
        generation.incrementAndGet();
        pending = false;
        Activity activity = getActivity();
        if (activity != null) runOnUiThread(() -> activity.stopService(new Intent(activity, CaptureService.class)));
        CaptureService.state = "stopped";
    }
    @UsedByGodot public String captureStatus() { return CaptureService.state; }
    @UsedByGodot public float captureLevel() {
        PlaybackCaptureSession active = CaptureService.session;
        return active == null ? 0f : active.currentLevel();
    }
    @Override public void onMainDestroy() { stopCapture(); }
}
