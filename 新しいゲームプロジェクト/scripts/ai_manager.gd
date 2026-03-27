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
		{"v": "v1beta", "m": "models/gemini-1.5-flash"},
		{"v": "v1", "m": "models/gemini-1.5-flash"},
		{"v": "v1beta", "m": "models/gemini-1.5-flash-8b"},
		{"v": "v1beta", "m": "models/gemini-1.5-flash-latest"},
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
	_try_generate_with_current_model()

func _try_generate_with_current_model():
	if _current_model_index >= _last_candidates.size():
		error_occurred.emit("全モデル試行失敗(404等)。キーを確認してください。")
		return
		
	var target = _last_candidates[_current_model_index]
	_actually_generate(_last_api_key, target["v"], target["m"])

func _actually_generate(api_key: String, version: String, model_path: String):
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

func _generate_via_js(url: String, body_data: String):
	# JavaScript を介して通信を行い、結果を callback で受け取る
	var js_code = """
	(async function(url, body) {
		try {
			const resp = await fetch(url, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: body
			});
			if (!resp.ok) {
				return JSON.stringify({error: 'HTTP ' + resp.status});
			}
			const data = await resp.json();
			return JSON.stringify(data);
		} catch (e) {
			return JSON.stringify({error: e.message});
		}
	})('""" + url + """', '""" + body_data.replace("'", "\\'") + """')
	"""
	
	# 同期的に結果を待つ（JSの実装によるが eval は非同期の結果を直接は返せないことが多い）
	# 代わりに非同期で実行し、window オブジェクト等に結果を置いてポーリングするか、
	# JavaScriptBridge.get_interface を使うが、簡易的に eval で同期的に試す
	var result = JavaScriptBridge.eval(js_code)
	if result:
		var json = JSON.new()
		if json.parse(result) == OK:
			var data = json.get_data()
			if data.has("error"):
				# 404 の場合はリトライ
				if data["error"].contains("404") and _current_model_index < _last_candidates.size() - 1:
					_current_model_index += 1
					_try_generate_with_current_model()
				else:
					error_occurred.emit("JS通信エラー: " + data["error"])
			else:
				# 成功
				_parse_gemini_response(data)
				return
	
	error_occurred.emit("JS通信の取得に失敗しました。")

func _on_request_completed(result, response_code, headers, body):
	if response_code == 404 and _current_model_index < _last_candidates.size() - 1:
		_current_model_index += 1
		_try_generate_with_current_model()
		return

	var response_text = body.get_string_from_utf8()
	if response_code != 200:
		var model_name = _last_candidates[_current_model_index]["m"]
		error_occurred.emit("生成エラー(" + str(response_code) + " @ " + model_name + "): " + response_text.left(50))
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
	
	error_occurred.emit("回答形式が不正です。")
