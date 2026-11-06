extends SceneTree
var failed = []
var checks = 0
class ClockFrame:
    extends "res://scripts/AnalysisFrame.gd"
    var clock = 2000
    func _now():
        return clock
func check(ok, name):
    checks += 1
    if not ok:
        failed.append(name)
        printerr("FAIL ", name)
func _init():
    var a = ClockFrame.new()
    check(a.begin_epoch(1), "new epoch")
    check(not a.begin_epoch(1), "epoch cannot rewind")
    var bands = []
    for i in range(16):
        bands.append(float(i)/16.0)
    check(a.publish(1, bands, .25, 1000, 1200, 300), "publish valid frame")
    var frame = a.snapshot(1100)
    check(frame["version"] == "tegra.analysis.v1" and frame["bands"].size() == 16, "portable shape")
    check(frame["source_age_ms"] == 100 and frame["rms"] == .25, "age and RMS")
    check(frame["beat"]["kind"] == "none", "FFT is not a beat detector")
    check(not a.publish(0, bands, .2, 1000, 1300, 200), "obsolete callback rejected")
    check(not a.publish(1, bands, .2, 900, 1300, 200), "sample clock cannot rewind")
    check(not a.publish(1, bands, .2, 1100, 1000, 200), "playback clock cannot rewind")
    bands[0] = 2.0
    check(not a.publish(1, bands, .2, 1100, 1300, 200), "invalid normalization rejected")
    bands[0] = 0.0
    a.configure_metronome(120)
    frame = a.snapshot(1100)
    check(frame["beat"]["kind"] == "configured_metronome" and abs(frame["beat"]["phase"]-.4) < .001 and frame["beat"]["confidence"] == 0.0, "configured phase without detector confidence")
    check(a.snapshot(1501)["source"] == "stale" and a.snapshot(1501)["bands"][15] == 0.0, "stale PCM expires")
    check(a.publish(1, bands, 0.0, 1600, 1400, 100), "silent PCM accepted")
    check(a.snapshot(1600)["source"] == "silent_pcm" and a.snapshot(1600)["bands"][15] == 0.0, "silence clears peaks")
    check(a.begin_epoch(2) and a.snapshot(1700)["source"] == "stale", "replacement clears old data")
    check(not a.publish(1, bands, .2, 1700, 1500, 100), "late replaced callback rejected")
    for invalid_epoch in [-1, 0, 2.5, "3", NAN, INF, 9007199254740992]:
        check(not a.begin_epoch(invalid_epoch), "invalid epoch cannot replace source")
        check(not a.publish(invalid_epoch, bands, .2, 1700, 1500, 100), "invalid epoch cannot publish")
    for invalid_time in [NAN, INF, -INF, -1, "1800", 9007199254740992]:
        var previous = a.sequence
        check(not a.publish(2, bands, .2, 1700, invalid_time, 100), "nonfinite or invalid playback rejected")
        check(a.sequence == previous, "invalid playback cannot mutate frame")
        check(not a.publish(2, bands, .2, 1700, 1500, invalid_time), "nonfinite or invalid latency rejected")
        check(not a.publish(2, bands, .2, invalid_time, 1500, 100), "nonfinite or invalid sample clock rejected")
    check(not a.publish(2, bands, .2, 2001, 1500, 100), "future source sample rejected")
    check(not a.publish(2, bands, .2, 1700.5, 1500, 100), "fractional source sample clock rejected")
    check(not a.publish(2, bands, .2, 1700, 1500, 10001), "latency budget bounded")
    check(not a.publish(2, {"wrong":"container"}, .2, 1700, 1500, 100), "wrong band container rejected safely")
    for invalid_number in [NAN, INF, -INF, "0.5", -1, 2]:
        check(not a.publish(2, bands, invalid_number, 1700, 1500, 100), "invalid RMS rejected")
        var invalid_bands = bands.duplicate()
        invalid_bands[0] = invalid_number
        check(not a.publish(2, invalid_bands, .2, 1700, 1500, 100), "invalid band rejected")
    check(a.publish(2, bands, .2, 1700, 1500.25, 100.5), "finite fractional playback and latency accepted")
    for invalid_snapshot in [-1, NAN, INF, "1800", 1700.5, 9007199254740992]:
        check(a.snapshot(invalid_snapshot)["source"] == "stale", "invalid snapshot clock expires safely")
    check(a.snapshot(1700)["source"] == "live_pcm", "valid clock recovers from rejected snapshot")
    check(a.snapshot(1699)["source"] == "stale", "rewound snapshot cannot appear fresh")
    check(a.snapshot(1699)["rms"] == 0.0, "rewound snapshot clears RMS")
    for invalid_bpm in [NAN, INF, "120", -1, 241]:
        check(not a.configure_metronome(invalid_bpm) and a.bpm == 0.0, "invalid configured BPM disables phase")
    print("ANALYSIS_CHECKS=", checks, " FAILURES=", failed)
    quit(0 if failed.empty() else 1)
