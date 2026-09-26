extends Node
## Procedural sound effects (autoload "Sfx").
##
## No audio files are shipped: every sound is synthesized once at startup into
## an AudioStreamWAV (16-bit mono). Playback uses small pools of players so no
## nodes are created during gameplay.

const MIX_RATE := 22050
const POOL_3D := 24
const POOL_2D := 8

var _streams: Dictionary = {}          # StringName -> AudioStreamWAV
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_sounds()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 600.0
		p.unit_size = 12.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# Distant sounds get muffled automatically (cheap "far gunshot" effect).
		p.attenuation_filter_cutoff_hz = 2500.0
		p.attenuation_filter_db = -18.0
		p.max_polyphony = 1
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool_2d.append(p2)


## Plays a positional sound. `pitch_var` randomizes pitch slightly for variety.
func play_3d(sound: StringName, pos: Vector3, volume_db := 0.0, pitch_var := 0.06, max_dist := 600.0) -> void:
	var stream: AudioStreamWAV = _streams.get(sound)
	if stream == null:
		return
	# Skip sounds that are too far away from the listener to be heard at all.
	if Game.camera != null and is_instance_valid(Game.camera):
		if Game.camera.global_position.distance_squared_to(pos) > max_dist * max_dist:
			return
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stream = stream
	p.max_distance = max_dist
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.global_position = pos
	p.play()


## Plays a non-positional sound (UI, own weapon, hit markers).
func play_2d(sound: StringName, volume_db := 0.0, pitch_var := 0.04) -> void:
	var stream: AudioStreamWAV = _streams.get(sound)
	if stream == null:
		return
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.play()


# --------------------------------------------------------------------------
# Synthesis
# --------------------------------------------------------------------------

func _build_sounds() -> void:
	_streams[&"rifle_shot"] = _make(_synth_gunshot(0.55, 95.0, 0.9))
	_streams[&"smg_shot"] = _make(_synth_gunshot(0.35, 135.0, 0.72))
	_streams[&"shotgun_shot"] = _make(_synth_gunshot(0.8, 68.0, 1.0))
	_streams[&"dmr_shot"] = _make(_synth_gunshot(0.7, 82.0, 0.95))
	_streams[&"sniper_shot"] = _make(_synth_gunshot(1.0, 58.0, 1.0))
	_streams[&"pistol_shot"] = _make(_synth_gunshot(0.3, 155.0, 0.68))
	_streams[&"punch"] = _make(_synth_thud(0.1, 85.0, 0.9))
	_streams[&"swish"] = _make(_synth_noise_burst(0.12, 0.08, 0.3))
	_streams[&"shell_in"] = _make(_synth_click(0.07, 1100.0, 0.8))
	_streams[&"dry_fire"] = _make(_synth_click(0.05, 2400.0, 0.5))
	_streams[&"mag_out"] = _make(_synth_click(0.09, 900.0, 0.7))
	_streams[&"mag_in"] = _make(_synth_click(0.1, 1300.0, 0.9))
	_streams[&"bolt"] = _make(_synth_bolt())
	_streams[&"hit_body"] = _make(_synth_thud(0.12, 110.0, 0.8))
	_streams[&"hit_head"] = _make(_synth_tone(0.22, 1750.0, 0.45, 9.0))
	_streams[&"hitmarker"] = _make(_synth_tone(0.05, 2600.0, 0.35, 60.0))
	_streams[&"kill"] = _make(_synth_tone(0.3, 880.0, 0.4, 7.0))
	_streams[&"impact"] = _make(_synth_noise_burst(0.07, 0.5, 0.35))
	_streams[&"whiz"] = _make(_synth_whiz())
	_streams[&"step"] = _make(_synth_noise_burst(0.06, 0.15, 0.25))
	_streams[&"ui_click"] = _make(_synth_tone(0.04, 1200.0, 0.3, 80.0))
	_streams[&"splash"] = _make(_synth_noise_burst(0.25, 0.35, 0.5))


func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


## Gunshot = sharp noise crack + low "thump" + filtered noise tail.
func _synth_gunshot(length: float, thump_hz: float, gain: float) -> PackedFloat32Array:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.35
		lp2 += (noise - lp2) * 0.06
		var crack := noise * exp(-t * 90.0)
		var body := lp * exp(-t * 18.0) * 0.9
		var tail := lp2 * exp(-t * 5.0) * 1.6
		var thump := sin(TAU * thump_hz * t * (1.0 - t)) * exp(-t * 22.0) * 0.9
		out[i] = (crack * 0.7 + body + tail + thump) * gain
	return out


func _synth_click(length: float, hz: float, gain: float) -> PackedFloat32Array:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 70.0)
		out[i] = (sin(TAU * hz * t) * 0.6 + _rng.randf_range(-1.0, 1.0) * 0.5) * env * gain
	return out


func _synth_bolt() -> PackedFloat32Array:
	var a := _synth_click(0.08, 700.0, 0.8)
	var b := _synth_click(0.1, 1500.0, 0.9)
	var gap := int(0.09 * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(a.size() + gap + b.size())
	for i in a.size():
		out[i] = a[i]
	for i in b.size():
		out[a.size() + gap + i] = b[i]
	return out


func _synth_thud(length: float, hz: float, gain: float) -> PackedFloat32Array:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.2
		out[i] = (sin(TAU * hz * t) * 0.8 + lp) * exp(-t * 30.0) * gain
	return out


func _synth_tone(length: float, hz: float, gain: float, decay: float) -> PackedFloat32Array:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var s := sin(TAU * hz * t) + 0.35 * sin(TAU * hz * 2.01 * t)
		out[i] = s * exp(-t * decay) * gain * minf(1.0, t * 400.0)
	return out


func _synth_noise_burst(length: float, smooth: float, gain: float) -> PackedFloat32Array:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * smooth
		out[i] = lp * exp(-t * (6.0 / length)) * gain * minf(1.0, t * 300.0)
	return out


## Bullet passing close by: short band-limited "zip" with falling pitch.
func _synth_whiz() -> PackedFloat32Array:
	var length := 0.18
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var hz := lerpf(2600.0, 900.0, t / length)
		phase += TAU * hz / MIX_RATE
		var env := sin(PI * t / length)
		out[i] = (sin(phase) * 0.5 + _rng.randf_range(-0.3, 0.3)) * env * 0.35
	return out
