extends Reference
# Restrict automatic D-pad traversal to the visible drawer, including its edges.
static func controls(node, result):
    for child in node.get_children():
        if child is Control and not child.is_visible_in_tree():
            continue
        if child is Control and child.focus_mode != Control.FOCUS_NONE and not (child is BaseButton and child.disabled):
            result.append(child)
        controls(child,result)

static func nested_popup(node):
    for child in node.get_children():
        if child is Popup and child.is_visible_in_tree():
            return true
        if nested_popup(child):
            return true
    return false

static func neighbour(current, choices, direction):
    var origin=current.get_global_rect().get_center()
    var best=current
    var score=INF
    for candidate in choices:
        if candidate==current:
            continue
        var delta=candidate.get_global_rect().get_center()-origin
        var forward=delta.dot(direction)
        if forward<=1.0:
            continue
        var sideways=abs(delta.dot(Vector2(-direction.y,direction.x)))
        var value=forward+sideways*2.0
        if value<score:
            score=value
            best=candidate
    return best
