extends Reference
# Separate, bounded app-gain setting. No account, media or device data.
const SAFE_DB=-60.0
const MAX_BYTES=1024
func valid(value):
    return typeof(value) in [TYPE_INT,TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value)) and value>=-60 and value<=0
func read(path):
    var file=File.new()
    if not file.file_exists(path): return {"ok":true,"found":false,"db":SAFE_DB}
    if file.open(path,File.READ)!=OK: return {"ok":false,"found":true,"db":SAFE_DB}
    var length=file.get_len()
    if length<1 or length>MAX_BYTES:
        file.close()
        return {"ok":false,"found":true,"db":SAFE_DB}
    var data=file.get_as_text();file.close()
    var config=ConfigFile.new()
    if config.parse(data)!=OK or config.get_value("volume","version",null)!=1:
        return {"ok":false,"found":true,"db":SAFE_DB}
    var db=config.get_value("volume","db",null)
    if not valid(db): return {"ok":false,"found":true,"db":SAFE_DB}
    return {"ok":true,"found":true,"db":float(db)}
func write(path,db):
    if not valid(db) or not read(path).ok: return false
    var config=ConfigFile.new()
    config.set_value("volume","version",1)
    config.set_value("volume","db",float(db))
    var temp=path+".tmp"
    if config.save(temp)!=OK: return false
    var staged=read(temp)
    var dir=Directory.new()
    if not staged.ok or not staged.found or not is_equal_approx(staged.db,float(db)) or not read(path).ok:
        dir.remove(temp)
        return false
    if dir.rename(temp,path)!=OK:
        dir.remove(temp)
        return false
    return true
