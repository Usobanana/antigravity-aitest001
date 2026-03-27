extends Control

# メインゲームロジック

@onready var ai_manager = $AIManager
@onready var status_label = $UI/StatusLabel
@onready var monster_name_label = $UI/MonsterInfo/NameLabel
@onready var monster_hp_bar = $UI/MonsterInfo/HPBar
@onready var log_label = $UI/LogLabel
@onready var spawn_button = $UI/Buttons/SpawnButton
@onready var attack_button = $UI/Buttons/AttackButton
@onready var api_key_input = $UI/APIKeyInput

var current_monster = {}
var player_hp = 100

func _ready():
	# 日本語フォントの適用
	var jp_font = load("res://fonts/japanese_font.tres")
	status_label.add_theme_font_override("font", jp_font)
	monster_name_label.add_theme_font_override("font", jp_font)
	log_label.add_theme_font_override("normal_font", jp_font)
	api_key_input.add_theme_font_override("font", jp_font)
	spawn_button.add_theme_font_override("font", jp_font)
	attack_button.add_theme_font_override("font", jp_font)

	ai_manager.monster_generated.connect(_on_monster_generated)
	ai_manager.error_occurred.connect(_on_ai_error)
	
	attack_button.disabled = true
	update_ui()

func update_ui():
	if current_monster.is_empty():
		monster_name_label.text = "モンスターを探索中..."
		monster_hp_bar.value = 0
	else:
		monster_name_label.text = current_monster["name"]
		monster_hp_bar.max_value = current_monster["hp"]
		monster_hp_bar.value = current_monster["current_hp"]

func _on_spawn_button_pressed():
	var key = api_key_input.text.strip_edges()
	if key.is_empty():
		status_label.text = "APIキーを入力してください"
		return
	status_label.text = "AI召喚中..."
	spawn_button.disabled = true
	ai_manager.generate_monster(key)

func _on_monster_generated(data):
	current_monster = data
	current_monster["current_hp"] = data["hp"]
	status_label.text = "モンスター出現！"
	log_label.text = data["greeting"]
	spawn_button.disabled = false
	attack_button.disabled = false
	update_ui()

func _on_ai_error(msg):
	status_label.text = "エラー発生"
	log_label.text = msg
	spawn_button.disabled = false

func _on_attack_button_pressed():
	if current_monster.is_empty(): return
	
	# プレイヤーの攻撃
	var damage = randi_range(10, 20)
	current_monster["current_hp"] -= damage
	log_label.text = "プレイヤーの攻撃！ " + str(damage) + " のダメージ！\n"
	
	if current_monster["current_hp"] <= 0:
		current_monster["current_hp"] = 0
		log_label.text += current_monster["death_cry"] + "\n勝利した！"
		attack_button.disabled = true
	else:
		# 敵の反撃（簡易版）
		var enemy_damage = current_monster["atk"]
		player_hp -= enemy_damage
		log_label.text += current_monster["name"] + " の反撃！ " + str(enemy_damage) + " のダメージ！"
	
	update_ui()
