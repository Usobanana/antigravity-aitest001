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
	
	_last_candidates = ["models/gemini-1.5-flash", "models/gemini-1.5-flash-latest", "models/gemini-1.5-pro", "models/gemini-pro"]
	if response_code == 200:
		var json = JSON.new()
		var parse_err = json.parse(response_text)
		if parse_err == OK:
			var data = json.get_data()
			var available = []
			if data.has("models"):
				for m in data["models"]:
					available.append(m["name"])
			if available.size() > 0:
				# 取得できた場合はそれも候補に加える（重複なし）
				for m in available:
					if not m in _last_candidates:
						_last_candidates.append(m)

	_current_model_index = 0
	_try_generate_with_current_model()

func _try_generate_with_current_model():
	if _current_model_index >= _last_candidates.size():
		error_occurred.emit("すべてのモデルで生成に失敗しました(404等)。")
		return
		
	var model_path = _last_candidates[_current_model_index]
	_actually_generate(_last_api_key, model_path)

func _actually_generate(api_key: String, model_path: String):
	var url = "https://generativelanguage.googleapis.com/v1beta/" + model_path + ":generateContent?key=" + api_key
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	var prompt = "あなたはRPGのモンスター生成器です。以下のJSON形式のみで返答してください。余計な説明は一切不要です。\n"
	prompt += "回答形式例: {\"name\": \"名前\", \"hp\": 50, \"atk\": 10, \"greeting\": \"出現!!\", \"death_cry\": \"ぐふっ\", \"image_prompt\": \"Engish keywords for monster image\"}\n"
	prompt += "指示: 新しいモンスターを1体生成。image_promptには、そのモンスターの姿を説明する短い英語キーワード(10語以内)を入れてください。"

	var body_data = JSON.stringify({
		"contents": [{ "parts": [{ "text": prompt }] }]
	})

	var headers = ["Content-Type: application/json"]
	http_request.request(url, headers, HTTPClient.METHOD_POST, body_data)

func _on_request_completed(result, response_code, headers, body):
	# 404エラーの場合は、次のモデル候補でリトライしてみる
	if response_code == 404 and _current_model_index < _last_candidates.size() - 1:
		_current_model_index += 1
		_try_generate_with_current_model()
		return

	var response_text = body.get_string_from_utf8()
	if response_code != 200:
		error_occurred.emit("生成エラー(" + str(response_code) + "): " + response_text.left(100))
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
