package au.local.shieldamp;

public final class SelfTaskCleanerTest {
    static int checks;
    static void check(boolean ok){checks++;if(!ok)throw new AssertionError("self task check "+checks);}
    public static void main(String[] args){
        String own="org.local.tegramilkdrop",godot="com.godot.game.GodotApp";
        check(SelfTaskCleaner.shouldRemove(42,41,own,own,godot));
        check(!SelfTaskCleaner.shouldRemove(42,42,own,own,godot));
        check(!SelfTaskCleaner.shouldRemove(-1,41,own,own,godot));
        check(!SelfTaskCleaner.shouldRemove(42,-1,own,own,godot));
        check(!SelfTaskCleaner.shouldRemove(42,41,own,"other.app",godot));
        check(!SelfTaskCleaner.shouldRemove(42,41,own,own+".other",godot));
        check(!SelfTaskCleaner.shouldRemove(42,41,own,own,"other.Activity"));
        check(!SelfTaskCleaner.shouldRemove(42,41,own,own,godot+"Other"));
        check(!SelfTaskCleaner.shouldRemove(42,41,null,own,godot));
        check(!SelfTaskCleaner.shouldRemove(42,41,own,null,null));
        check(!SelfTaskCleaner.shouldRemove(42,41,"",own,godot));
        System.out.println("SELF_TASK_CLEANER_CHECKS="+checks);
    }
}
