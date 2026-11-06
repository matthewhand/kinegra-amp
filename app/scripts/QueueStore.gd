extends Reference
# Stable local catalog indices only. No media, URLs or credentials.
const MAX_BYTES=16384
const MAX_QUEUE=1024
func valid(items, maximum=1028):
    if typeof(items)!=TYPE_ARRAY or items.size()>MAX_QUEUE: return false
    for index in items:
        if typeof(index)!=TYPE_INT or index<0 or index>=maximum: return false
    return true
func read(path):
    var f=File.new()
    if not f.file_exists(path): return {"ok":true,"items":[]}
    if f.open(path,File.READ)!=OK: return {"ok":false,"items":[]}
    var length=f.get_len()
    if length<1 or length>MAX_BYTES:
        f.close()
        return {"ok":false,"items":[]}
    var contents=f.get_as_text()
    f.close()
    var cfg=ConfigFile.new()
    if cfg.parse(contents)!=OK or not cfg.get_value("queue","version",0) in [1,2]:
        return {"ok":false,"items":[]}
    var items=cfg.get_value("queue","items",null)
    if not valid(items,4 if cfg.get_value("queue","version")==1 else 1028): return {"ok":false,"items":[]}
    return {"ok":true,"items":items.duplicate()}
func write(path,items):
    if not valid(items) or not read(path)["ok"]: return false
    var cfg=ConfigFile.new()
    cfg.set_value("queue","version",2)
    cfg.set_value("queue","items",items.duplicate())
    var temp=path+".tmp"
    if cfg.save(temp)!=OK: return false
    var f=File.new()
    if f.open(temp,File.READ)!=OK: return false
    var size=f.get_len()
    f.close()
    var dir=Directory.new()
    if size<1 or size>MAX_BYTES:
        dir.remove(temp)
        return false
    if dir.rename(temp,path)!=OK:
        dir.remove(temp)
        return false
    return true
