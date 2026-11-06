extends Reference
# Shared validation only. Credentials are never part of an endpoint or setting.
func origin(value, schemes, trust_private_cleartext=false):
    if typeof(value) != TYPE_STRING or value.length() > 256:
        return {}
    var split = value.find("://")
    if split < 1:
        return {}
    var scheme = value.substr(0, split)
    if not scheme in schemes:
        return {}
    var authority = value.substr(split + 3).trim_suffix("/")
    for i in range(authority.length()):
        if not authority.substr(i, 1).to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789.:-":
            return {}
    var parts = authority.split(":")
    if parts.size() > 2 or parts[0].empty() or parts[0].begins_with(".") or parts[0].ends_with("."):
        return {}
    var secure = scheme in ["https", "wss"]
    var port = 443 if secure else 80
    if parts.size() == 2:
        if not parts[1].is_valid_integer() or int(parts[1]) < 1 or int(parts[1]) > 65535:
            return {}
        port = int(parts[1])
    if not secure:
        var host = parts[0]
        var octets = host.split(".")
        var private_ip = host.is_valid_ip_address() and octets.size() == 4 and (octets[0] == "10" or host == "127.0.0.1" or (octets[0] == "192" and octets[1] == "168") or (octets[0] == "172" and int(octets[1]) >= 16 and int(octets[1]) <= 31))
        if not trust_private_cleartext or not private_ip:
            return {}
    return {"host": parts[0], "port": port, "secure": secure, "prefix": scheme + "://" + authority}
