package org.godotengine.godot.plugin;
/** Proof-only host API: executes unchanged plugin Java, not Godot JNI. */
public abstract class GodotPlugin {
    private final org.godotengine.godot.Godot godot;
    public GodotPlugin(org.godotengine.godot.Godot godot){this.godot=godot;}
    protected android.app.Activity getActivity(){return godot.getActivity();}
    public void onMainResume(){}
    public abstract String getPluginName();
}
