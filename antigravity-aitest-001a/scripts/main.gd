extends Control

# メインゲームロジック (新プロジェクト Ver 0.1)

@onready var ai_manager = $AIManager
@onready var status_label = $UI/StatusLabel
@onready var monster_name_label = $UI/MonsterInfo/NameLabel
@onready var monster_hp_bar = $UI/MonsterInfo/HPBar
@onready var log_label = $UI/LogLabel
@onready var spawn_button = $UI/Buttons/SpawnButton
@onready var attack_button = $UI/Buttons/AttackButton
@onready var api_key_input = $UI/KeyInputHBox/APIKeyInput
@onready var key_prompt_button = $UI/KeyInputHBox/KeyPromptButton
@onready var copy_log_button = $UI/CopyLogButton
@onready var monster_image = $UI/MonsterInfo/MonsterImage

const SAVE_PATH = "user://settings.cfg"
const APP_VERSION = "Ver 0.2"
const STYLE_PROMPT = "digital illustration, dark fantasy, epic, highly detailed, cinematic lighting, centered on solid dark background"

var image_http_request: HTTPRequest
var current_monster = {}
var player_hp = 100

func _ready():
	# 日本語フォントとサイズの適用
	var jp_font = load("res://assets/fonts/jp_font.ttf")
	if jp_font:
		var font_size = 32
		var title_size = 48
		
		status_label.add_theme_font_override("font", jp_font)
		status_label.add_theme_font_size_override("font_size", font_size)
		
		monster_name_label.add_theme_font_override("font", jp_font)
		monster_name_label.add_theme_font_size_override("font_size", title_size)
		
		log_label.add_theme_font_override("normal_font", jp_font)
		log_label.add_theme_font_size_override("normal_font_size", font_size)
		
		api_key_input.add_theme_font_override("font", jp_font)
		api_key_input.add_theme_font_size_override("font_size", font_size)
		api_key_input.secret = false
		
		spawn_button.add_theme_font_override("font", jp_font)
		spawn_button.add_theme_font_size_override("font_size", font_size)
		
		attack_button.add_theme_font_override("font", jp_font)
		attack_button.add_theme_font_size_override("font_size", font_size)

	ai_manager.monster_generated.connect(_on_monster_generated)
	ai_manager.error_occurred.connect(_on_ai_error)
	ai_manager.status_label = status_label
	ai_manager.APP_VERSION = APP_VERSION
	
	attack_button.disabled = true
	status_label.text = APP_VERSION + " - 準備完了"
	
	image_http_request = HTTPRequest.new()
	add_child(image_http_request)
	image_http_request.request_completed.connect(_on_image_request_completed)
	
	key_prompt_button.pressed.connect(_on_key_prompt_button_pressed)
	copy_log_button.pressed.connect(_on_copy_log_button_pressed)
	
	load_api_key()
	update_ui()

func load_api_key():
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		var raw_key = config.get_value("api", "key", "")
		var clean_key = raw_key.replace(" ", "").replace("\r", "").replace("\n", "").replace("\u00A0", "").strip_edges()
		api_key_input.text = clean_key

func save_api_key(key: String):
	var config = ConfigFile.new()
	config.set_value("api", "key", key)
	config.save(SAVE_PATH)

func update_ui():
	if current_monster.is_empty():
		monster_name_label.text = "モンスターを探索中..."
		monster_hp_bar.value = 0
	else:
		monster_name_label.text = current_monster["name"]
		monster_hp_bar.max_value = current_monster["hp"]
		monster_hp_bar.value = current_monster["current_hp"]

func _on_spawn_button_pressed():
	var key = api_key_input.text
	key = key.replace(" ", "").replace("\r", "").replace("\n", "").replace("\u00A0", "").strip_edges()
	if key.is_empty():
		status_label.text = "APIキーを入力してください"
		return
	
	save_api_key(key)
	status_label.text = APP_VERSION + " - AI召喚中..."
	spawn_button.disabled = true
	ai_manager.generate_monster(key)

func _on_key_prompt_button_pressed():
	if OS.has_feature("web"):
		var js_code = "prompt('Gemini APIキーを貼り付けてください', '');"
		var result = JavaScriptBridge.eval(js_code)
		if result != null and result != "":
			api_key_input.text = result
			save_api_key(result)
			status_label.text = APP_VERSION + " - キーを設定しました"

func _on_copy_log_button_pressed():
	var full_text = log_label.get_parsed_text()
	if OS.has_feature("web"):
		var escaped_text = full_text.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
		var js_code = "navigator.clipboard.writeText('" + escaped_text + "').then(() => alert('ログをコピーしました'));"
		JavaScriptBridge.eval(js_code)
	else:
		DisplayServer.clipboard_set(full_text)
		status_label.text = "ログをコピーしました"

func _on_monster_generated(data):
	current_monster = data
	current_monster["current_hp"] = data["hp"]
	status_label.text = APP_VERSION + " - モンスター出現！"
	log_label.text = data["greeting"]
	spawn_button.disabled = false
	attack_button.disabled = false
	if data.has("image_prompt"):
		_fetch_monster_image(data["image_prompt"])
	update_ui()

func _on_ai_error(msg):
	status_label.text = APP_VERSION + " - エラー発生"
	log_label.text = msg
	spawn_button.disabled = false

func _fetch_monster_image(prompt: String):
	monster_image.texture = null
	var combined_prompt = prompt + ", " + STYLE_PROMPT
	var url = "https://image.pollinations.ai/prompt/" + combined_prompt.uri_encode() + "?width=512&height=512&nologo=true&seed=" + str(randi())
	log_label.text += "\n[color=gray](画像を生成中...)[/color]"
	image_http_request.request(url, [], HTTPClient.METHOD_GET)

func _on_image_request_completed(result, response_code, headers, body):
	if result != OK or response_code != 200:
		if !monster_image.texture:
			var fallback_url = "https://robohash.org/" + current_monster["name"].uri_encode() + "?set=set2"
			image_http_request.request(fallback_url, [], HTTPClient.METHOD_GET)
		return
	var image = Image.new()
	var err = image.load_jpg_from_buffer(body)
	if err != OK: err = image.load_png_from_buffer(body)
	if err == OK:
		monster_image.texture = ImageTexture.create_from_image(image)
		log_label.text += "\n[color=green](画像を表示しました)[/color]"

func _on_attack_button_pressed():
	if current_monster.is_empty(): return
	var damage = randi_range(10, 20)
	current_monster["current_hp"] -= damage
	log_label.text = "プレイヤーの攻撃！ " + str(damage) + " のダメージ！\n"
	if current_monster["current_hp"] <= 0:
		current_monster["current_hp"] = 0
		status_label.text = APP_VERSION + " - 討伐完了！"
		log_label.text += current_monster["death_cry"] + "\n勝利した！"
		play_death_animation()
		spawn_button.disabled = false
		attack_button.disabled = true
	else:
		shake_monster()
		flash_monster()
		var enemy_damage = current_monster["atk"]
		player_hp -= enemy_damage
		log_label.text += current_monster["name"] + " の反撃！ " + str(enemy_damage) + " のダメージ！"
	update_ui()

func shake_monster():
	var tween = create_tween()
	var original_pos = monster_image.position
	for i in range(4):
		var offset = Vector2(randf_range(-10, 10), randf_range(-10, 10))
		tween.tween_property(monster_image, "position", original_pos + offset, 0.05)
	tween.tween_property(monster_image, "position", original_pos, 0.05)

func flash_monster():
	var tween = create_tween()
	tween.tween_property(monster_image, "modulate", Color.RED, 0.1)
	tween.tween_property(monster_image, "modulate", Color.WHITE, 0.1)

func play_death_animation():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(monster_image, "self_modulate:a", 0.0, 0.5)
	tween.tween_property(monster_image, "scale", Vector2(0.5, 0.5), 0.5)
	tween.tween_property(monster_image, "rotation", deg_to_rad(15), 0.5)
