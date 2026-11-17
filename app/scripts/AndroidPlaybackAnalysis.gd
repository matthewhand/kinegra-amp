extends Reference

static func _in_range(value, lower, upper):
    return typeof(value) in [TYPE_INT, TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value)) and value >= lower and value <= upper

static func read(raw, expected_generation, now_ms):
    if typeof(raw) != TYPE_STRING or raw.empty() or raw.length() > 1024: return {}
    var parsed = JSON.parse(raw)
    if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY: return {}
    var result = parsed.result
    var generation = result.get("generation")
    var age = result.get("age_ms")
    var position_ms = result.get("playback_ms")
    var rms = result.get("rms")
    var bands = result.get("bands")
    if not _in_range(generation, 0, 2147483647) or generation != expected_generation: return {}
    if not _in_range(age, 0, min(now_ms, 500)) or age != int(age): return {}
    if not _in_range(position_ms, 0.0, 9007199254740991.0) or not _in_range(rms, 0.0, 1.0): return {}
    if typeof(bands) != TYPE_ARRAY or bands.size() != 16: return {}
    for value in bands:
        if not _in_range(value, 0.0, 1.0): return {}
    return {"generation":int(generation),"sample_at":now_ms-int(age),"playback_ms":position_ms,"rms":rms,"bands":bands}
