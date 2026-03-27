extends Node

# AI管理クラス: Gemini 1.5 Flash API との通信を担当

const API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key="

signal monster_generated(data: Dictionary)
signal error_occurred(message: String)

func generate_monster(api_key: String):
	if api_key.is_empty():
		error_occurred.emit("APIキーが設定されていません。")
		return

	# デバッグ用: まずはモデルリストを取得してみる (疎通確認)
	var list_url = "https://generativelanguage.googleapis.com/v1beta/models?key=" + api_key
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_debug_completed.bind(api_key))
	http_request.request(list_url, [], HTTPClient.METHOD_GET)

func _on_debug_completed(result, response_code, headers, body, api_key):
	var response_text = body.get_string_from_utf8()
	if response_code != 200:
		error_occurred.emit("デバッグ疎通失敗(" + str(response_code) + "): " + response_text.left(100))
		return
	
	# リスト取得成功したら、そのままモンスター生成へ
	_actually_generate(api_key)

func _actually_generate(api_key: String):
	var url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" + api_key
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	var prompt = "あなたはRPGのモンスター生成器です。以下のJSON形式のみで返答してください。余計な説明は一切不要です。\n"
	prompt += "回答形式例: {\"name\": \"名前\", \"hp\": 50, \"atk\": 10, \"greeting\": \"出現!!\", \"death_cry\": \"ぐふっ\"}\n"
	prompt += "指示: 新しいモンスターを1体生成。"

	var body_data = JSON.stringify({
		"contents": [{ "parts": [{ "text": prompt }] }]
	})

	var headers = ["Content-Type: application/json"]
	http_request.request(url, headers, HTTPClient.METHOD_POST, body_data)

func _on_request_completed(result, response_code, headers, body):
	var response_text = body.get_string_from_utf8()
	if response_code != 200:
		error_occurred.emit("生成エラー(" + str(response_code) + "): " + response_text.left(100))
		return

	var json = JSON.new()
	var parse_err = json.parse(response_text)
	if parse_err == OK:
		var response = json.get_data()
		if response.has("candidates") and response["candidates"].size() > 0:
			var content = response["candidates"][0]["content"]["parts"][0]["text"]
			var inner_json = JSON.new()
			# 余計なマークダウン記法(```json ... ```)を削除
			var clean_content = content.replace("```json", "").replace("```", "").strip_edges()
			var inner_err = inner_json.parse(clean_content)
			if inner_err == OK:
				monster_generated.emit(inner_json.get_data())
				return
	
	error_occurred.emit("解析失敗: " + response_text.left(50))
