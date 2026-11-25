class_name AiHttp
extends RefCounted
## Small async HTTP helpers (each call gets its own HTTPRequest node, so
## several requests can run at once). Use with `await`.

## Returns {ok: bool, code: int, body: PackedByteArray, error: String}.
static func request(owner: Node, url: String, headers: PackedStringArray = PackedStringArray(), method: int = HTTPClient.METHOD_GET, body: PackedByteArray = PackedByteArray(), timeout: float = 60.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.use_threads = true
	http.download_chunk_size = 262144
	owner.add_child(http)
	var err := http.request_raw(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "body": PackedByteArray(), "error": "Could not start the request to %s (%s)" % [url, error_string(err)]}
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var data: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": code, "body": data, "error": _result_text(result, url)}
	if code < 200 or code >= 300:
		var txt := data.get_string_from_utf8().left(600)
		return {"ok": false, "code": code, "body": data, "error": "HTTP %d from %s: %s" % [code, url, txt]}
	return {"ok": true, "code": code, "body": data, "error": ""}


static func get_json(owner: Node, url: String, headers: PackedStringArray = PackedStringArray(), timeout: float = 30.0) -> Dictionary:
	var r := await request(owner, url, headers, HTTPClient.METHOD_GET, PackedByteArray(), timeout)
	return _with_json(r)


static func post_json(owner: Node, url: String, payload: Variant, headers: PackedStringArray = PackedStringArray(), timeout: float = 120.0) -> Dictionary:
	var h := headers.duplicate()
	h.append("Content-Type: application/json")
	var r := await request(owner, url, h, HTTPClient.METHOD_POST, JSON.stringify(payload).to_utf8_buffer(), timeout)
	return _with_json(r)


## Adds `json` (parsed body, or null) to a request result.
static func _with_json(r: Dictionary) -> Dictionary:
	var body: PackedByteArray = r.get("body", PackedByteArray())
	r["json"] = null
	if body.size() > 0:
		var j := JSON.new()
		if j.parse(body.get_string_from_utf8()) == OK:
			r["json"] = j.data
	return r


static func _result_text(result: int, url: String) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Can't connect to %s — is it running?" % url.get_slice("/", 2)
		HTTPRequest.RESULT_TIMEOUT:
			return "%s took too long to answer." % url.get_slice("/", 2)
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Secure connection to %s failed." % url.get_slice("/", 2)
	return "Request to %s failed (code %d)." % [url.get_slice("/", 2), result]


## multipart/form-data body builder.
class Multipart:
	var boundary: String = "----StrataAI%d" % randi()
	var _buf := PackedByteArray()

	func field(field_name: String, value: String) -> void:
		_buf.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, field_name, value]).to_utf8_buffer())

	func file(field_name: String, file_name: String, data: PackedByteArray, mime: String = "image/png") -> void:
		_buf.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % [boundary, field_name, file_name, mime]).to_utf8_buffer())
		_buf.append_array(data)
		_buf.append_array("\r\n".to_utf8_buffer())

	func finish() -> PackedByteArray:
		var out := _buf.duplicate()
		out.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
		return out
