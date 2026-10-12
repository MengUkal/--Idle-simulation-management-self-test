extends Node
## 音频接入层：SFX 播放池（SFX 总线）+ BGM 切换（Music 总线）。
## 音频产物由 tools/audiogen.py 生成（音频会话负责，见 docs/音频制作计划.md）；
## 文件缺失时静默跳过——本层先入库，产物一出即响。触发点命名与 audiogen.py 的
## CATALOG / SONGS 对齐（sfx/<name>.wav、bgm/<name>.ogg）。
## 音量由用户设置的 Music/SFX 总线控制（设置页三滑条，即时生效）。

const SFX_DIR := "res://assets/audio/sfx/"
const BGM_DIR := "res://assets/audio/bgm/"
const AMB_DIR := "res://assets/audio/amb/"
const POOL_SIZE := 10

var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _bgm_player: AudioStreamPlayer
var _bgm_current := ""
var _amb_player: AudioStreamPlayer
var _amb_current := ""
var _cache := {}
var _essence_last := -1      # -1 = 尚未初始化（读档/重生当次不响）
var _essence_cooldown := 0.0


func _ready() -> void:
	_ensure_buses()  # 代码兜底创建 Music/SFX 总线（project.godot 的 [audio] 段会被编辑器写回吞掉，此处不依赖它）
	Settings.apply_audio()  # 总线就绪后重新应用用户音量（Settings._ready 先于本层跑过一次，当时总线缺失被跳过）
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Music"
	add_child(_bgm_player)
	_amb_player = AudioStreamPlayer.new()
	_amb_player.bus = "Music"
	_amb_player.volume_db = -4.0  # 环境音垫底：文件本身 RMS≈0.045，再压 4dB 藏在 BGM 下（随 Music 滑条）
	add_child(_amb_player)
	# 精华入账音：精华「增加」时才响（训练消耗不响），节流防刷屏（音频会话补接线）
	EventBus.essence_changed.connect(_on_essence_changed)


func _process(delta: float) -> void:
	if _essence_cooldown > 0.0:
		_essence_cooldown -= delta


func _on_essence_changed(total: int) -> void:
	if _essence_last >= 0 and total > _essence_last and _essence_cooldown <= 0.0:
		play("essence_gain")
		_essence_cooldown = 0.5
	_essence_last = total


## 播一个命名音效（可带 pitch：连锁升调用）。产物缺失或未导入时静默跳过。
## 变体轮播：存在同名 _b/_c 变体文件时随机轮播防腻，缺失自动回退本体（2026-10-11 音频会话）。
func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream := _pick_variant(name)
	if stream == null:
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = stream
	p.pitch_scale = maxf(0.1, pitch)
	p.volume_db = volume_db
	p.play()


func _pick_variant(base: String) -> AudioStream:
	var main := _load_stream(SFX_DIR + base + ".wav")
	if main == null:
		return null
	var pool: Array = [main]
	for suffix in ["_b", "_c"]:
		var v := _load_stream(SFX_DIR + base + suffix + ".wav")
		if v != null:
			pool.append(v)
	return pool[randi() % pool.size()]


## 切换 BGM（同名且在播则忽略，避免场景往返重头播）。ogg 循环双保险（导入设置+代码）。
## 环境音随 BGM 联动：bgm_floorN → amb_floorN，其余（交易所等）无环境音（2026-10-11 音频会话）。
func bgm(name: String) -> void:
	if _bgm_current == name and _bgm_player.playing:
		return
	var stream := _load_stream(BGM_DIR + name + ".ogg")
	if stream == null:
		stream = _load_stream(BGM_DIR + name + ".wav")  # WAV 回退（程序化 BGM，2026-10-12）
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2  # 16bit 单声道：样本数 = 字节数/2
	_bgm_current = name
	_bgm_player.stream = stream
	_bgm_player.play()
	_play_amb(_amb_for(name))


func _amb_for(bgm_name: String) -> String:
	if bgm_name.begins_with("bgm_floor"):
		return "amb_" + bgm_name.trim_prefix("bgm_")
	return ""


func _play_amb(amb: String) -> void:
	if _amb_current == amb and (_amb_player.playing or amb == ""):
		return
	_amb_current = amb
	if amb == "":
		_amb_player.stop()
		return
	var stream := _load_stream(AMB_DIR + amb + ".ogg")
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_amb_player.stream = stream
	_amb_player.play()


func bgm_stop() -> void:
	_bgm_current = ""
	_bgm_player.stop()


## 代码兜底：确保 Music/SFX 总线存在并发送 Master。
## 不依赖 project.godot 的 [audio] 段——那段会被开着编辑器的会话写回时吞掉（2026-10-11 事故）。
func _ensure_buses() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	_play_amb("")


func _load_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	_cache[path] = stream
	return stream
