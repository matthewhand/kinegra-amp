extends Node
# The platform picker alone handles document URIs. Godot receives safe counts only.
signal status_changed
var music = null
var platform = null
var state = "idle"
var imported = 0
var skipped = 0
var errors = 0
var _elapsed = 0.0
const ACTIVE = ["choosing","copying","cancelling"]
const STATES = ["idle","choosing","copying","cancelling","complete","cancelled","timed_out","error","picker_unavailable"]

func _ready():
    if platform == null and OS.get_name() == "Android" and Engine.has_singleton("ShieldAmpTokenStore"):
        platform = Engine.get_singleton("ShieldAmpTokenStore")
    set_process(false)

func begin():
    if state in ACTIVE: return false
    if music == null or music.user_library.blocked:
        state = "error"
        emit_signal("status_changed")
        return false
    Directory.new().make_dir_recursive(music.user_library.directory)
    if platform == null:
        state = "picker_unavailable"
        emit_signal("status_changed")
        return false
    # JNI singleton.has_method does not advertise Java @UsedByGodot methods.
    var accepted = platform.beginOfflineImport(ProjectSettings.globalize_path(music.user_library.directory))
    if typeof(accepted) != TYPE_BOOL or not accepted:
        state = "error"
        emit_signal("status_changed")
        return false
    state = "choosing"
    imported = 0
    skipped = 0
    errors = 0
    _elapsed = 0.0
    set_process(true)
    emit_signal("status_changed")
    return true

func cancel():
    if not state in ACTIVE or platform == null: return false
    var accepted = platform.cancelOfflineImport()
    if typeof(accepted) == TYPE_BOOL and accepted:
        state = "cancelling"
        emit_signal("status_changed")
        return true
    return false

func _process(delta):
    _elapsed += delta
    if _elapsed < 0.5: return
    _elapsed = 0.0
    _poll()

func _poll():
    if platform == null or not state in ACTIVE: return
    var text = platform.offlineImportStatus()
    if typeof(text) != TYPE_STRING or text.length() > 1024: return
    var parsed = JSON.parse(text)
    if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY: return
    var value = parsed.result
    if not value.get("state","") in STATES: return
    var total = 0
    for key in ["imported","skipped","errors"]:
        var count = value.get(key,0)
        # Native reports one selection-overflow error plus at most 32 file
        # outcomes. Accept that terminal boundary without relaxing copy limits.
        var limit = 33 if key == "errors" else 32
        if not typeof(count) in [TYPE_INT,TYPE_REAL] or is_nan(float(count)) or is_inf(float(count)) or count < 0 or count > limit or count != int(count): return
        total += int(count)
    if int(value.get("imported",0)) + int(value.get("skipped",0)) > 32 or total > 33: return
    state = value.state
    imported = int(value.get("imported",0))
    skipped = int(value.get("skipped",0))
    errors = int(value.get("errors",0))
    if not state in ACTIVE:
        set_process(false)
        if music != null: music.refresh_user_library()
    emit_signal("status_changed")

func message():
    match state:
        "idle":return "MP3 / OGG  •  USB OR INTERNAL STORAGE  •  COPIES STAY ON THIS DEVICE"
        "choosing":return "CHOOSE MP3 / OGG FILES IN THE SYSTEM PICKER"
        "copying":return "COPYING  •  %d IMPORTED / %d SKIPPED / %d ERRORS" % [imported,skipped,errors]
        "cancelling":return "CANCELLING  •  WAITING FOR STORAGE PROVIDER"
        "complete":return "%d IMPORTED / %d ALREADY PRESENT / %d ERRORS  •  NO AUTOPLAY" % [imported,skipped,errors]
        "cancelled":return "IMPORT CANCELLED  •  USB ORIGINALS UNCHANGED"
        "timed_out":return "STORAGE PROVIDER TIMED OUT  •  TRY AGAIN"
        "picker_unavailable":return "SYSTEM FILE PICKER UNAVAILABLE ON THIS DEVICE"
        _:return "IMPORT COULD NOT FINISH  •  AVAILABLE COPIES KEPT"
