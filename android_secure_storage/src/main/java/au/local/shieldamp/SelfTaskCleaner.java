package au.local.shieldamp;

/** Exact own-Godot-task policy; never a global recents/task cleanup. */
final class SelfTaskCleaner {
    static boolean shouldRemove(int current,int candidate,String ownPackage,String basePackage,String baseClass){
        return current>=0&&candidate>=0&&candidate!=current&&ownPackage!=null&&!ownPackage.isEmpty()
            &&ownPackage.equals(basePackage)&&"com.godot.game.GodotApp".equals(baseClass);
    }
}
