extends SceneTree
var failures=[]
var latest={}
func check(ok,label):
    print("ARTWORK_METADATA_"+("PASS_" if ok else "FAIL_")+label)
    if not ok:failures.append(label)
func snapshot(value):latest=value
func reply(catalog,value):
    catalog.request_node=HTTPRequest.new();catalog.add_child(catalog.request_node)
    catalog.request_context={"kind":"local_queue_read","queue_id":"own-wrapper"}
    catalog._complete(HTTPRequest.RESULT_SUCCESS,200,[],to_json(value).to_utf8(),catalog.epoch)
func _init():call_deferred("run")
func run():
    var catalog=load("res://scripts/MACatalog.gd").new();get_root().add_child(catalog)
    var id="a".repeat(64)
    var raw={"item_id":"1","provider":"library","name":"Synthetic","media_type":"track","metadata":{"images":[{"type":"thumb","proxy_id":id,"path":"https://external.invalid/private?token=credential"}]},"provider_mappings":[{"url":"private"}]}
    var row=catalog._row(raw,"tracks")
    check(row.get("artwork_descriptor",{}).get("proxy_id")==id and row["artwork_descriptor"].size()==1,"catalog_row_carries_only_validated_opaque_artwork_id")
    check(to_json(row).find("external.invalid")==-1 and not row.has("metadata") and not row.has("provider_mappings"),"raw_artwork_urls_and_provider_metadata_do_not_escape_adapter")
    catalog.current_page={"items":[row]};catalog.select_index(0)
    check(catalog.selected.get("artwork_descriptor",{}).get("proxy_id")==id,"explicit_selection_preserves_safe_artwork_descriptor")
    catalog.connect("local_queue_snapshot",self,"snapshot")
    var current={"name":"Synthetic","queue_item_id":"current","media_item":{"album":{"image":{"proxy_id":id}}}}
    reply(catalog,{"queue_id":"own-wrapper","state":"playing","current_item":current})
    check(latest.get("artwork_descriptor",{}).get("proxy_id")==id,"queue_snapshot_uses_same_bounded_album_fallback_contract")
    reply(catalog,{"queue_id":"own-wrapper","state":"playing","current_item":{"name":"Other","queue_item_id":"next","image":{"path":"https://external.invalid/image.png"}}})
    check(latest.get("artwork_descriptor",{"unexpected":true}).empty(),"track_without_proxy_id_clears_previous_artwork_descriptor")
    catalog.queue_free();print("ARTWORK_METADATA_FAILURES=",failures.size());quit(0 if failures.empty() else 1)
