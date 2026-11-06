extends Reference
# Keep existing valid casting first; replace only a collision or unavailable style.
static func assign(lead,styles,preferred,count=2):
    var allowed=[]
    if typeof(styles)==TYPE_ARRAY:
        for value in styles:
            if typeof(value)==TYPE_STRING and not value.empty() and not value in allowed:allowed.append(value)
    var result=[]
    var used=[lead]
    for index in range(clamp(int(count),0,8)):result.append("")
    for index in range(result.size()):
        var previous=preferred[index] if typeof(preferred)==TYPE_ARRAY and index<preferred.size() else ""
        if previous in allowed and not previous in used:
            result[index]=previous
            used.append(previous)
    for index in range(result.size()):
        if not result[index].empty():continue
        for value in allowed:
            if not value in used:
                result[index]=value
                used.append(value)
                break
    return result # An empty slot is honest when too few distinct styles exist.
