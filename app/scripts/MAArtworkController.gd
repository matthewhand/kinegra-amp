extends Node
# One bounded same-origin image request; session-only RAM cache, never a disk cache.
signal artwork_ready(context,texture)
signal authorization_failed
const Policy=preload("res://scripts/MAArtworkPolicy.gd")
var connection_policy=preload("res://scripts/ConnectionPolicy.gd").new()
var _origin=""
var _credential=""
var _trust=false
var _session_epoch=-1
var _generation=0
var _request=null
var _requested=""
var _cache={}
var _lru=[]
func is_configured():return not _origin.empty()
func matches_session(origin,credential,trust,epoch):
    return _origin==origin and _credential==credential and _trust==trust and _session_epoch==epoch
func configure(origin,credential,trust,epoch):
    if matches_session(origin,credential,trust,epoch):return not _origin.empty()
    close()
    if typeof(origin)!=TYPE_STRING or connection_policy.origin(origin,["https","http"],trust).empty():return false
    if typeof(credential)!=TYPE_STRING or credential.length()<10 or credential.length()>8192:return false
    for index in range(credential.length()):
        if credential.ord_at(index)<33 or credential.ord_at(index)>126:return false
    _origin=origin
    _credential=credential
    _trust=trust
    _session_epoch=epoch
    return true
func cancel_current():
    _generation+=1
    if _request!=null:
        _request.cancel_request()
        _request.queue_free()
        _request=null
    _requested=""
func close():
    cancel_current()
    _origin=""
    _credential=""
    _session_epoch=-1
    _cache.clear()
    _lru.clear()
func select(descriptor,context):
    var safe=Policy.descriptor(descriptor)
    var id=safe.get("proxy_id","")
    var key=context+"|"+id
    if _requested==key:return not id.empty()
    cancel_current()
    _requested=key
    if _origin.empty() or id.empty():return false
    if _cache.has(id):
        _lru.erase(id)
        _lru.append(id)
        emit_signal("artwork_ready",context,_cache[id])
        return true
    _request=HTTPRequest.new()
    _request.body_size_limit=Policy.MAX_BODY
    _request.timeout=5.0
    _request.max_redirects=0
    _request.download_chunk_size=16384
    add_child(_request)
    _request.connect("request_completed",self,"_complete",[_generation,context,id])
    # Never accept a supplied URL, provider path, origin or query string.
    var error=_request.request(_origin+"/imageproxy/"+id+"?size=256&fmt=png",["Authorization: Bearer "+_credential,"Accept: image/png","Accept-Encoding: identity"],true,HTTPClient.METHOD_GET)
    if error!=OK:
        _dispose()
        emit_signal("artwork_ready",context,null)
        return false
    return true
func _dispose():
    if _request!=null:
        _request.queue_free()
        _request=null
func _complete(result,code,headers,body,generation,context,id):
    if generation!=_generation:return
    _dispose()
    if code in [401,403]:
        close()
        emit_signal("authorization_failed")
        emit_signal("artwork_ready",context,null)
        return
    var content_type=""
    var types=0
    var encoding=""
    for header in headers:
        var split=str(header).find(":")
        if split>=0 and str(header).substr(0,split).strip_edges().to_lower()=="content-type":
            content_type=str(header).substr(split+1).strip_edges().to_lower().split(";")[0]
            types+=1
        elif split>=0 and str(header).substr(0,split).strip_edges().to_lower()=="content-encoding":encoding=str(header).substr(split+1).strip_edges().to_lower()
    var geometry=Policy.png_geometry(body)
    if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or types!=1 or content_type!="image/png" or not encoding in ["","identity"] or geometry==Vector2.ZERO:
        emit_signal("artwork_ready",context,null)
        return
    var image=Image.new()
    if image.load_png_from_buffer(body)!=OK or image.get_width()!=int(geometry.x) or image.get_height()!=int(geometry.y):
        emit_signal("artwork_ready",context,null)
        return
    if image.get_width()>Policy.TEXTURE_EDGE or image.get_height()>Policy.TEXTURE_EDGE:
        var scale=min(float(Policy.TEXTURE_EDGE)/image.get_width(),float(Policy.TEXTURE_EDGE)/image.get_height())
        image.resize(max(1,int(image.get_width()*scale)),max(1,int(image.get_height()*scale)),Image.INTERPOLATE_BILINEAR)
    var texture=ImageTexture.new()
    texture.create_from_image(image,0)
    if _cache.size()>=Policy.CACHE_ENTRIES:
        _cache.erase(_lru.pop_front())
    _cache[id]=texture
    _lru.append(id)
    emit_signal("artwork_ready",context,texture)
func _notification(what):
    if what==MainLoop.NOTIFICATION_APP_PAUSED:close()
func _exit_tree():close()
