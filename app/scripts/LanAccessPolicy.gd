extends Reference
const PRIVATE_BLOCKS=[[167772160,184549375],[2886729728,2887778303],[3232235520,3232301055],[2130706432,2147483647],[2851995648,2852061183]]
func ip_number(value):
    var parts=str(value).split(".")
    if parts.size()!=4:return -1
    var result=0
    for part in parts:
        if not part.is_valid_integer() or int(part)<0 or int(part)>255 or str(int(part))!=part:return -1
        result=result*256+int(part)
    return result
func _private_range(low,high):
    for block in PRIVATE_BLOCKS:
        if low>=block[0] and high<=block[1]:return true
    return false
func parse(text):
    if typeof(text)!=TYPE_STRING or text.length()>512:return {"ok":false,"error":"Use up to eight private IPv4 ranges."}
    var entries=text.replace("\n",",").replace(";",",").split(",",false)
    if entries.empty() or entries.size()>8:return {"ok":false,"error":"Enter one to eight trusted LAN ranges, such as 10.42.0.0/24."}
    var ranges=[]
    var labels=[]
    for entry in entries:
        var value=entry.strip_edges()
        var low=-1
        var high=-1
        if "-" in value:
            var pair=value.split("-")
            if pair.size()!=2:return {"ok":false,"error":"Use IPv4, CIDR, or start-end ranges."}
            low=ip_number(pair[0].strip_edges());high=ip_number(pair[1].strip_edges())
        elif "/" in value:
            var pair=value.split("/")
            if pair.size()!=2 or not pair[1].is_valid_integer():return {"ok":false,"error":"Invalid CIDR prefix."}
            var prefix=int(pair[1]);var ip=ip_number(pair[0])
            if prefix<0 or prefix>32 or ip<0:return {"ok":false,"error":"Invalid IPv4 CIDR range."}
            var mask=4294967295 ^ ((1 << (32-prefix))-1)
            low=ip & mask;high=low+((1 << (32-prefix))-1)
        else:
            low=ip_number(value)
            high=low
        if low<0 or high<low or not _private_range(low,high):return {"ok":false,"error":"Ranges must stay within private LAN, link-local or loopback IPv4 space."}
        ranges.append([low,high]);labels.append(value)
    return {"ok":true,"ranges":ranges,"text":PoolStringArray(labels).join(", ")}
func allows(address,ranges):
    var ip=ip_number(address)
    if ip<0:return false
    for bounds in ranges:
        if ip>=bounds[0] and ip<=bounds[1]:return true
    return false
func starter(addresses):
    var found=["127.0.0.1/32"]
    for address in addresses:
        if ip_number(address)<0 or str(address).begins_with("127."):continue
        var parts=str(address).split(".")
        var range_text=parts[0]+"."+parts[1]+"."+parts[2]+".0/24"
        if parse(range_text).ok and not range_text in found and found.size()<8:found.append(range_text)
    return PoolStringArray(found).join(", ")
