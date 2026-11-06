extends AcceptDialog
# Bounded read-only pages keep long upstream notices usable on a TV.
const PAGE_CHARS = 24000
var components = null
var viewer = null
var previous = null
var next = null
var counter = null
var entries = []
var content = ""
var page = 0
func _ready():
    window_title = "Licenses & notices"
    get_ok().text = "CLOSE"
    var stack = VBoxContainer.new()
    stack.set_anchors_and_margins_preset(Control.PRESET_WIDE)
    stack.margin_left = 16
    stack.margin_right = -16
    stack.margin_top = 12
    stack.margin_bottom = -56
    add_child(stack)
    components = OptionButton.new()
    components.rect_min_size.y = 48
    stack.add_child(components)
    components.connect("item_selected", self, "_select")
    viewer = TextEdit.new()
    viewer.readonly = true
    viewer.wrap_enabled = true
    viewer.virtual_keyboard_enabled = false
    viewer.context_menu_enabled = false
    viewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    viewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    viewer.rect_min_size.y = 120
    stack.add_child(viewer)
    var row = HBoxContainer.new()
    stack.add_child(row)
    previous = Button.new()
    previous.text = "PREVIOUS PAGE"
    previous.rect_min_size.y = 48
    row.add_child(previous)
    previous.connect("pressed", self, "_previous")
    counter = Label.new()
    counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    counter.align = Label.ALIGN_CENTER
    row.add_child(counter)
    next = Button.new()
    next.text = "NEXT PAGE"
    next.rect_min_size.y = 48
    row.add_child(next)
    next.connect("pressed", self, "_next")
    var file = File.new()
    if file.open("res://assets/notices/INDEX.json", File.READ) == OK:
        var parsed = JSON.parse(file.get_as_text())
        file.close()
        if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
            for entry in parsed.result.get("notices", []):
                if typeof(entry) == TYPE_DICTIONARY and typeof(entry.get("file")) == TYPE_STRING and entry.file.get_file() == entry.file:
                    entries.append(entry)
                    components.add_item(str(entry.get("title", entry.file)))
    if entries.empty():
        viewer.text = "No notice bundle is installed. This package is incomplete."
        previous.disabled = true
        next.disabled = true
        counter.text = "UNAVAILABLE"
    else:
        _select(0)
func open():
    popup_centered_ratio(0.92)
    components.grab_focus()
func _select(index):
    if index < 0 or index >= entries.size(): return
    var file = File.new()
    content = "Notice unavailable."
    if file.open("res://assets/notices/" + entries[index].file, File.READ) == OK:
        if file.get_len() <= 2 * 1024 * 1024:
            content = file.get_as_text()
        file.close()
    page = 0
    _render()
func _render():
    var pages = max(1, int(ceil(float(content.length()) / PAGE_CHARS)))
    page = clamp(page, 0, pages - 1)
    viewer.text = content.substr(page * PAGE_CHARS, PAGE_CHARS)
    viewer.cursor_set_line(0)
    previous.disabled = page == 0
    next.disabled = page + 1 >= pages
    counter.text = "%d / %d" % [page + 1, pages]
func _previous():
    page -= 1
    _render()
func _next():
    page += 1
    _render()
