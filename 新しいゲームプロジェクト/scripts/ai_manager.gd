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
	
	# v1 と v1beta の両方を試すための候補リスト
	_last_candidates = [
		{"v": "v1", "m": "models/gemini-1.5-flash"},
		{"v": "v1beta", "m": "models/gemini-1.5-flash"},
		{"v": "v1", "m": "models/gemini-1.5-pro"},
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
	# エンドポイントを動的に構築
	var url = "https://generativelanguage.googleapis.com/" + version + "/" + model_path + ":generateContent?key=" + api_key
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	var prompt = "あなたはRPGのモンスター生成器です。以下のJSON形式のみで返答してください。余計な説明は一切不要です。\n"
	prompt += "回答形式例: {\"name\": \"名前\", \"hp\": 50, \"atk\": 10, \"greeting\": \"出現!!\", \"death_cry\": \"ぐふっ\", \"image_prompt\": \"Engish keywords for monster image\"}\n"
	prompt += "指示: 新しいモンスターを1体生成。"

	var body_data = JSON.stringify({
		"contents": [{ "parts": [{ "text": prompt }] }]
	})

	var headers = ["Content-Type: application/json"]
	http_request.request(url, headers, HTTPClient.METHOD_POST, body_data)

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
	var parse_err = json.parse(response_text)
	if parse_err == OK:
		var response = json.get_data()
		if response.has("candidates") and response["candidates"].size() > 0:
			var part = response["candidates"][0]["content"]["parts"][0]
			if part.has("text"):
				var content = part["text"]
				# JSON抽出とパース
				var inner_json = JSON.new()
				var clean_content = content.replace("```json", "").replace("```", "").strip_edges()
				var inner_err = inner_json.parse(clean_content)
				if inner_err == OK:
					monster_generated.emit(inner_json.get_data())
					return
	
	error_occurred.emit("解析失敗: " + response_text.left(50))
