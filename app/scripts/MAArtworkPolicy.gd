extends Reference
# Opaque image IDs only. Never retain provider paths, external URLs or credentials.
# MA 2.10.7 metadata/images.py canonical /imageproxy/<sha256>?size=&fmt=.
const MAX_BODY=524288
const MAX_EDGE=512
const MAX_PIXELS=262144
const TEXTURE_EDGE=256
const CACHE_ENTRIES=4
static func descriptor(value):
    if typeof(value)!=TYPE_DICTIONARY or typeof(value.get("proxy_id"))!=TYPE_STRING:return {}
    var id=value["proxy_id"]
    if id.length()!=64:return {}
    for index in range(64):
        if not id.substr(index,1) in "0123456789abcdef":return {}
    return {"proxy_id":id}
static func _images(media):
    var result=[]
    if typeof(media)!=TYPE_DICTIONARY:return result
    if typeof(media.get("image"))==TYPE_DICTIONARY:result.append(media["image"])
    var metadata=media.get("metadata")
    if typeof(metadata)==TYPE_DICTIONARY and typeof(metadata.get("images"))==TYPE_ARRAY:
        for index in range(min(16,metadata["images"].size())):
            var image=metadata["images"][index]
            if typeof(image)==TYPE_DICTIONARY and image.get("type")=="thumb":result.append(image)
    return result
static func sanitize(media):
    if typeof(media)!=TYPE_DICTIONARY:return {}
    var candidates=_images(media)
    var item=media.get("media_item")
    if typeof(item)==TYPE_DICTIONARY:
        candidates+=_images(item)
    else:item=media
    var album=item.get("album")
    candidates+=_images(album)
    for image in candidates:
        var safe=descriptor(image)
        if not safe.empty():return safe
    return {}
static func _be32(bytes,offset):
    return (int(bytes[offset])<<24)|(int(bytes[offset+1])<<16)|(int(bytes[offset+2])<<8)|int(bytes[offset+3])
static func png_geometry(bytes):
    # Inspect IHDR before handing compressed data to an allocating decoder.
    if not (bytes is PoolByteArray) or bytes.size()<33 or bytes.size()>MAX_BODY:return Vector2.ZERO
    var signature=[137,80,78,71,13,10,26,10]
    for index in range(8):
        if bytes[index]!=signature[index]:return Vector2.ZERO
    if _be32(bytes,8)!=13 or bytes.subarray(12,15).get_string_from_ascii()!="IHDR":return Vector2.ZERO
    var width=_be32(bytes,16)
    var height=_be32(bytes,20)
    if width<1 or height<1 or width>MAX_EDGE or height>MAX_EDGE or width*height>MAX_PIXELS:return Vector2.ZERO
    return Vector2(width,height)
