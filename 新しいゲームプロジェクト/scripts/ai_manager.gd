extends Node

# AI管理クラス: Gemini 1.5 Flash API との通信を担当

const API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key="

signal monster_generated(data: Dictionary)
signal error_occurred(message: String)

var _last_api_key = ""
var _last_candidates = []
var _current_model_index = 0

func generate_monster(api_key: String):
	if api_key.is_empty():
		error_occurred.emit("APIキーが設定されていません。")
		return

	_last_api_key = api_key
	# デバッグ用: まずはモデルリストを取得してみる
	var list_url = "https://generativelanguage.googleapis.com/v1beta/models?key=" + api_key
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_debug_completed.bind(api_key))
	http_request.request(list_url, [], HTTPClient.METHOD_GET)

func _on_debug_completed(result, response_code, headers, body, api_key):
	var response_text = body.get_string_from_utf8()
	
	# v1 と v1beta の両方、および最新の 8b モデルを含む候補
	_last_candidates = [
		{"v": "v1beta", "m": "models/gemini-1.5-flash-latest"},
		{"v": "v1beta", "m": "models/gemini-1.5-flash"},
		{"v": "v1", "m": "models/gemini-1.5-flash"},
		{"v": "v1beta", "m": "models/gemini-1.5-flash-8b"},
		{"v": "v1beta", "m": "models/gemini-1.5-pro"},
		{"v": "v1", "m": "models/gemini-pro"}
	]
	
	if response_code == 200:
		var json = JSON.new()
		var parse_err = json.parse(response_text)
		if parse_err == OK:
			var data = json.get_data()
			if data.has("models"):
				for m in data["models"]:
					var mname = m["name"]
					# 重複チェック
					var found = false
					for c in _last_candidates:
						if c["m"] == mname: found = true
					if not found:
						_last_candidates.append({"v": "v1beta", "m": mname})

	_current_model_index = 0
	_error_history = ""

func _try_generate_with_current_model():
	if _current_model_index >= _last_candidates.size():
		error_occurred.emit("全モデル試行失敗:\n" + _error_history)
		return
		
	var target = _last_candidates[_current_model_index]
	status_label.text = APP_VERSION + " - AI召喚中(" + target["m"].split("/")[-1] + ")..."
	_actually_generate(_last_api_key, target["v"], target["m"])

func _actually_generate(api_key: String, version: String, model_path: String):
	# 最もシンプルな ?key= 方式（カスタムヘッダーによるプリフライト 404 回避）
	var url = "https://generativelanguage.googleapis.com/" + version + "/" + model_path + ":generateContent?key=" + api_key
	
	var prompt = "RPGモンスター生成(JSON形式のみ): {\"name\":\"名前\",\"hp\":50,\"atk\":10,\"greeting\":\"出現!\",\"death_cry\":\"ぐふっ\",\"image_prompt\":\"English monster appearance keywords\"}"
	var body_data = JSON.stringify({
		"contents": [{ "parts": [{ "text": prompt }] }]
	})

	# Web環境（iOS等）では Godot の HTTPRequest ではなく JS の fetch を試す（CORS/404対策）
	if OS.has_feature("web"):
		_generate_via_js(url, body_data)
		return

	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	var headers = ["Content-Type: application/json"]
	http_request.request(url, headers, HTTPClient.METHOD_POST, body_data)

var _js_callback_ref # コールバック参照保持用

func _generate_via_js(url_raw: String, body_data_raw: String):
	_js_callback_ref = JavaScriptBridge.create_callback(_on_js_fetch_completed)
	var window = JavaScriptBridge.get_interface("window")
	window.godot_fetch_callback = _js_callback_ref
	
	# 引数を URI エンコードして JS 側に渡す（バッククォートやエスケープ消失を防ぐ）
	var encoded_body = body_data_raw.uri_encode()
	
	var js_code = """
	(async function(url, enc_body) {
		const body = decodeURIComponent(enc_body);
		try {
			const resp = await fetch(url, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: body
			});
			const status = resp.status;
			let data = {};
			try { data = await resp.json(); } catch(e) { data = {message: 'No JSON response'}; }
			window.godot_fetch_callback(JSON.stringify({
				ok: resp.ok,
				error: 'HTTP ' + status, 
				code: status, 
				details: JSON.stringify(data)
			}));
		} catch (e) {
			window.godot_fetch_callback(JSON.stringify({ok: false, error: e.message, code: 0}));
		}
	})('""" + url_raw + """', '""" + encoded_body + """')
	"""
	JavaScriptBridge.eval(js_code)

func _on_js_fetch_completed(args):
	var result_json = args[0]
	var json = JSON.new()
	if json.parse(result_json) == OK:
		var data = json.get_data()
		if !data.get("ok", false):
			var code = data.get("code", 0)
			var mname = _last_candidates[_current_model_index]["m"]
			_error_history += "[" + mname + "] " + str(data["error"]) + " " + str(data.get("details", "")) + "\n"
			
			# 次のモデルへ
			_current_model_index += 1
			_try_generate_with_current_model()
		else:
			_parse_gemini_response(data)
	else:
		error_occurred.emit("JS通信結果のパース失敗")

func _on_request_completed(result, response_code, headers, body):
	var response_text = body.get_string_from_utf8()
	if response_code != 200:
		var mname = _last_candidates[_current_model_index]["m"]
		_error_history += "[" + mname + "] HTTP " + str(response_code) + " " + response_text.left(100) + "\n"
		
		# 次のモデルへ
		_current_model_index += 1
		_try_generate_with_current_model()
		return

	var json = JSON.new()
	if json.parse(response_text) == OK:
		_parse_gemini_response(json.get_data())
	else:
		error_occurred.emit("解析失敗: " + response_text.left(50))

func _parse_gemini_response(response: Dictionary):
	if response.has("candidates") and response["candidates"].size() > 0:
		var part = response["candidates"][0]["content"]["parts"][0]
		if part.has("text"):
			var content = part["text"]
			var inner_json = JSON.new()
			var clean_content = content.replace("```json", "").replace("```", "").strip_edges()
			if inner_json.parse(clean_content) == OK:
				monster_generated.emit(inner_json.get_data())
				return
	
	_error_history += "形式エラー\n"
	_current_model_index += 1
	_try_generate_with_current_model()
