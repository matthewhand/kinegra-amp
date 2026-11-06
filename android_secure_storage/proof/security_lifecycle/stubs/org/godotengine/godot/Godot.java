package org.godotengine.godot;
/** Standalone proof host only; never included in the production plugin AAR. */
public final class Godot {
    private final android.app.Activity activity;
    public Godot(android.app.Activity activity){this.activity=activity;}
    public android.app.Activity getActivity(){return activity;}
}
