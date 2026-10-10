extends Node
## 音频接入层：SFX 播放池（SFX 总线）+ BGM 切换（Music 总线）。
## 音频产物由 tools/audiogen.py 生成（音频会话负责，见 docs/音频制作计划.md）；
## 文件缺失时静默跳过——本层先入库，产物一出即响。触发点命名与 audiogen.py 的
## CATALOG / SONGS 对齐（sfx/<name>.wav、bgm/<name>.ogg）。
## 音量由用户设置的 Music/SFX 总线控制（设置页三滑条，即时生效）。

const SFX_DIR := "res://assets/audio/sfx/"
const BGM_DIR := "res://assets/audio/bgm/"
const POOL_SIZE := 10

var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _bgm_player: AudioStreamPlayer
var _bgm_current := ""
var _cache := {}


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Music"
	add_child(_bgm_player)


## 播一个命名音效（可带 pitch：连锁升调用）。产物缺失或未导入时静默跳过。
func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream := _load_stream(SFX_DIR + name + ".wav")
	if stream == null:
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = stream
	p.pitch_scale = maxf(0.1, pitch)
	p.volume_db = volume_db
	p.play()


## 切换 BGM（同名且在播则忽略，避免场景往返重头播）。ogg 循环双保险（导入设置+代码）。
func bgm(name: String) -> void:
	if _bgm_current == name and _bgm_player.playing:
		return
	var stream := _load_stream(BGM_DIR + name + ".ogg")
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_bgm_current = name
	_bgm_player.stream = stream
	_bgm_player.play()


func bgm_stop() -> void:
	_bgm_current = ""
	_bgm_player.stop()


func _load_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	_cache[path] = stream
	return stream
