extends Node

# AI管理クラス: Gemini 1.5 Flash API との通信を担当

const API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key="

signal monster_generated(data: Dictionary)
signal error_occurred(message: String)

func generate_monster(api_key: String):
	if api_key.is_empty():
		error_occurred.emit("APIキーが設定されていません。")
		return

	var url = API_URL + api_key
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	var prompt = "あなたはRPGのモンスター生成器です。以下のJSON形式のみで返答してください。余計な説明は一切不要です。\n"
	prompt += "回答形式例:\n"
	prompt += "{\n  \"name\": \"名前\",\n  \"hp\": 50,\n  \"atk\": 10,\n  \"greeting\": \"出現時のセリフ(20文字以内)\",\n  \"death_cry\": \"敗北時のセリフ(20文字以内)\"\n}\n"
	prompt += "指示: 新しいユニークなモンスターを1体生成してください。HPは30〜100、ATKは5〜20の範囲にしてください。"

	var body = JSON.stringify({
		"contents": [{
			"parts": [{ "text": prompt }]
		}],
		"generationConfig": {
			"response_mime_type": "application/json"
		}
	})

	var headers = ["Content-Type: application/json"]
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		error_occurred.emit("リクエストの開始に失敗しました。")

func _on_request_completed(result, response_code, headers, body):
	if response_code != 200:
		error_occurred.emit("APIエラー: ステータスコード " + str(response_code))
		return

	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		error_occurred.emit("JSONの解析に失敗しました。")
		return

	var response = json.get_data()
	if response.has("candidates") and response["candidates"].size() > 0:
		var content = response["candidates"][0]["content"]["parts"][0]["text"]
		var inner_json = JSON.new()
		var inner_err = inner_json.parse(content)
		if inner_err == OK:
			monster_generated.emit(inner_json.get_data())
		else:
			error_occurred.emit("生成されたテキストが有効なJSONではありません。")
	else:
		error_occurred.emit("有効なレスポンスが得られませんでした。")
