extends Node2D
## IKAN BUNTAL
## Makan ikan kecil, hindari ubur-ubur, dan KEMBUNG saat pemangsa mendekat:
## duri ikan buntal bikin mereka kabur. Semua gambar dibuat lewat kode (_draw).

const W := 1280.0
const H := 720.0
const FLOOR_Y := 630.0
const SAVE_PATH := "user://ikan_buntal.cfg"
const PUFF_BTN := Vector2(W - 120.0, H - 120.0)
const PUFF_R := 78.0
const JOY_C := Vector2(160.0, H - 150.0)
const JOY_R := 100.0
const PAUSE_C := Vector2(W * 0.5, 46.0)
const PAUSE_R := 32.0
const BASE0 := 30.0  # radius dasar ikan buntal saat level 1

enum State { MENU, PLAY, PAUSED, OVER }


class Critter:
	var kind: String = "small"  # small | pred | jelly | air
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var r: float = 10.0
	var phase: float = 0.0
	var col: Color = Color.WHITE
	var mode: String = "normal"  # normal | flee
	var cd: float = 0.0
	var age: float = 0.0
	var anchor: float = 0.0
	var dir: float = 1.0
	var face: float = 1.0
	var dead: bool = false


class Particle:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var life: float = 0.0
	var max_life: float = 1.0
	var col: Color = Color.WHITE
	var r: float = 3.0


class FloatText:
	var pos: Vector2 = Vector2.ZERO
	var text: String = ""
	var life: float = 1.2
	var col: Color = Color.WHITE


var state: int = State.MENU
var t_total: float = 0.0
var font: Font
var fish_tex: Texture2D

# Pemain
var p_pos := Vector2(W * 0.5, H * 0.45)
var p_vel := Vector2.ZERO
var p_face: float = 1.0
var p_base: float = BASE0
var p_base_target: float = BASE0
var p_puff: float = 0.0
var p_air: float = 1.0
var p_exhausted: bool = false
var p_invuln: float = 0.0
var p_wig: float = 0.0
var mouth_t: float = 0.0

var lives: int = 3
var score: int = 0
var best: int = 0
var new_best: bool = false
var eaten: int = 0
var level: int = 1
var game_time: float = 0.0
var over_delay: float = 0.0
var shake: float = 0.0
var flash: float = 0.0

# Input
var target_active: bool = false
var target_pos := Vector2.ZERO
var move_touch: int = -2
var touch_vec := Vector2.ZERO
var puff_touches: Dictionary = {}
var mouse_left: bool = false
var mouse_right: bool = false
var show_touch_ui: bool = false

# Dunia
var critters: Array[Critter] = []
var particles: Array[Particle] = []
var texts: Array[FloatText] = []
var bg_bubbles: Array[Vector3] = []  # x, y, radius
var weeds: Array[Vector3] = []  # x, tinggi, fase

var small_t: float = 0.0
var pred_t: float = 7.0
var jelly_t: float = 12.0
var air_t: float = 8.0

# Warna
var c_body := Color.html("#f6b93b")
var c_belly := Color.html("#ffe9a8")
var c_line := Color.html("#8b5a1b")
var c_dark := Color.html("#2a1a0a")
var small_colors: Array[Color] = [
	Color.html("#5ad1c8"),
	Color.html("#ff8fb1"),
	Color.html("#a6e35d"),
	Color.html("#ffd166"),
	Color.html("#b69cff"),
]


func _ready() -> void:
	randomize()
	font = ThemeDB.fallback_font
	fish_tex = load("res://assets/ikan_buntal.png") as Texture2D
	show_touch_ui = DisplayServer.is_touchscreen_available()
	load_best()
	for i in 28:
		bg_bubbles.append(Vector3(randf_range(0.0, W), randf_range(0.0, H), randf_range(2.0, 7.0)))
	for i in 16:
		weeds.append(Vector3(randf_range(0.0, W), randf_range(70.0, 150.0), randf() * TAU))


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			match k.physical_keycode:
				KEY_ENTER, KEY_KP_ENTER:
					try_start()
				KEY_SPACE:
					if state != State.PLAY:
						try_start()
				KEY_P, KEY_ESCAPE:
					toggle_pause()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and state == State.PLAY and mb.position.distance_to(PAUSE_C) <= PAUSE_R * 1.3:
				toggle_pause()
			else:
				mouse_left = mb.pressed
				if mb.pressed:
					try_start()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			mouse_right = mb.pressed
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		target_pos = mm.position
		target_active = true
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		show_touch_ui = true
		if st.pressed:
			if state != State.PLAY:
				try_start()
			elif st.position.distance_to(PAUSE_C) <= PAUSE_R * 1.4:
				toggle_pause()
			elif st.position.distance_to(PUFF_BTN) <= PUFF_R * 1.25:
				puff_touches[st.index] = true
			elif move_touch == -2 and st.position.distance_to(JOY_C) <= JOY_R * 1.5:
				move_touch = st.index
				touch_vec = (st.position - JOY_C).limit_length(JOY_R)
		else:
			puff_touches.erase(st.index)
			if st.index == move_touch:
				move_touch = -2
				touch_vec = Vector2.ZERO
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		if sd.index == move_touch:
			touch_vec = (sd.position - JOY_C).limit_length(JOY_R)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAY:
		state = State.PAUSED


func try_start() -> void:
	match state:
		State.MENU:
			start_game()
		State.OVER:
			if over_delay <= 0.0:
				start_game()
		State.PAUSED:
			state = State.PLAY


func toggle_pause() -> void:
	if state == State.PLAY:
		state = State.PAUSED
	elif state == State.PAUSED:
		state = State.PLAY


# ---------------------------------------------------------------- game flow

func start_game() -> void:
	critters.clear()
	particles.clear()
	texts.clear()
	p_pos = Vector2(W * 0.5, H * 0.45)
	p_vel = Vector2.ZERO
	p_face = 1.0
	p_base = BASE0
	p_base_target = BASE0
	p_puff = 0.0
	p_air = 1.0
	p_exhausted = false
	p_invuln = 1.0
	mouth_t = 0.0
	lives = 3
	score = 0
	eaten = 0
	level = 1
	game_time = 0.0
	new_best = false
	shake = 0.0
	flash = 0.0
	small_t = 0.0
	pred_t = 7.0
	jelly_t = 12.0
	air_t = 8.0
	for i in 5:
		spawn_small()
		critters[critters.size() - 1].pos.x = randf_range(120.0, W - 120.0)
	state = State.PLAY


func end_game() -> void:
	state = State.OVER
	over_delay = 0.8
	flash = 0.6
	shake = 0.5
	if score > best:
		best = score
		new_best = true
		save_best()
	burst(p_pos, Color(1.0, 0.8, 0.3), 26, 260.0)


func load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("game", "best", 0))


func save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "best", best)
	cfg.save(SAVE_PATH)


func add_score(n: int) -> void:
	score += n


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	t_total += dt
	update_background(dt)
	match state:
		State.PLAY:
			update_play(dt)
		State.MENU, State.OVER:
			over_delay = maxf(0.0, over_delay - dt)
			update_effects(dt)
	shake = maxf(0.0, shake - dt)
	flash = maxf(0.0, flash - dt)
	position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 16.0
	queue_redraw()


func update_background(dt: float) -> void:
	for i in bg_bubbles.size():
		var b: Vector3 = bg_bubbles[i]
		b.y -= (10.0 + b.z * 6.0) * dt
		if b.y < -10.0:
			b = Vector3(randf_range(0.0, W), H + 10.0, b.z)
		bg_bubbles[i] = b


func update_play(dt: float) -> void:
	game_time += dt
	p_invuln = maxf(0.0, p_invuln - dt)
	mouth_t = maxf(0.0, mouth_t - dt)
	p_base = lerpf(p_base, p_base_target, 1.0 - exp(-3.0 * dt))
	update_player(dt)
	spawn_logic(dt)
	update_critters(dt)
	update_effects(dt)


func player_radius() -> float:
	return lerpf(p_base * 1.05, p_base * 2.0, p_puff)


func update_player(dt: float) -> void:
	var want_puff: bool = (
		Input.is_physical_key_pressed(KEY_SPACE)
		or Input.is_physical_key_pressed(KEY_SHIFT)
		or mouse_left
		or mouse_right
		or not puff_touches.is_empty()
	)
	if p_exhausted:
		want_puff = false
		if p_air >= 0.35:
			p_exhausted = false

	if want_puff and p_air > 0.0:
		p_puff = minf(1.0, p_puff + dt * 5.0)
		p_air = maxf(0.0, p_air - dt * 0.28)
		if p_air <= 0.0:
			p_exhausted = true
			add_text(p_pos + Vector2(0.0, -60.0), "Capek...", Color(1.0, 0.6, 0.5))
	else:
		p_puff = maxf(0.0, p_puff - dt * 3.5)
		p_air = minf(1.0, p_air + dt * 0.25)

	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		dir.y += 1.0

	var max_speed: float = lerpf(270.0, 150.0, p_puff)
	var desired := Vector2.ZERO
	if not dir.is_zero_approx():
		desired = dir.normalized() * max_speed
		target_active = false
	elif move_touch != -2:
		var tl: float = touch_vec.length()
		if tl > 10.0:
			desired = touch_vec / tl * max_speed * clampf(tl / (JOY_R * 0.7), 0.0, 1.0)
	elif target_active:
		var to: Vector2 = target_pos - p_pos
		var d: float = to.length()
		if d > 8.0:
			desired = to / d * minf(max_speed, d * 5.0)

	p_vel = p_vel.lerp(desired, 1.0 - exp(-6.0 * dt))
	p_pos += p_vel * dt
	if absf(p_vel.x) > 20.0:
		p_face = signf(p_vel.x)
	p_wig += dt * (5.0 + p_vel.length() * 0.04)

	var rr: float = player_radius()
	p_pos.x = clampf(p_pos.x, rr, W - rr)
	p_pos.y = clampf(p_pos.y, rr + 10.0, FLOOR_Y + 15.0 - rr * 0.5)

	if p_vel.length() > 60.0 and randf() < dt * 4.0:
		burst(p_pos + Vector2(p_face * rr, -rr * 0.2), Color(0.85, 0.97, 1.0, 0.7), 1, 25.0)


func spawn_logic(dt: float) -> void:
	var n_small: int = 0
	var n_pred: int = 0
	var n_jelly: int = 0
	var n_air: int = 0
	for c in critters:
		match c.kind:
			"small":
				n_small += 1
			"pred":
				n_pred += 1
			"jelly":
				n_jelly += 1
			"air":
				n_air += 1

	small_t -= dt
	if small_t <= 0.0:
		small_t = randf_range(0.4, 0.9)
		if n_small < 7 + level:
			spawn_small()

	pred_t -= dt
	if pred_t <= 0.0:
		pred_t = maxf(3.0, 8.0 - float(level) * 0.5) + randf() * 2.0
		if n_pred < mini(1 + int(level / 2.0), 4):
			spawn_pred()

	jelly_t -= dt
	if jelly_t <= 0.0:
		jelly_t = randf_range(6.0, 10.0)
		if level >= 2 and n_jelly < 1 + int(level / 3.0):
			spawn_jelly()

	air_t -= dt
	if air_t <= 0.0:
		air_t = randf_range(6.0, 10.0)
		if n_air < 2:
			spawn_air()


func spawn_small() -> void:
	var c := Critter.new()
	c.kind = "small"
	c.r = randf_range(9.0, minf(14.0 + float(level) * 2.0, p_base_target * 0.85))
	c.dir = 1.0 if randf() < 0.5 else -1.0
	c.face = c.dir
	c.pos = Vector2(-100.0 if c.dir > 0.0 else W + 100.0, randf_range(70.0, FLOOR_Y - 60.0))
	c.anchor = c.pos.y
	c.vel = Vector2(c.dir * randf_range(70.0, 140.0), 0.0)
	c.phase = randf() * TAU
	c.col = small_colors[randi() % small_colors.size()]
	critters.append(c)


func spawn_pred() -> void:
	var c := Critter.new()
	c.kind = "pred"
	c.r = randf_range(36.0, 44.0) + float(level) * 1.5
	c.dir = 1.0 if randf() < 0.5 else -1.0
	c.face = c.dir
	c.pos = Vector2(-150.0 if c.dir > 0.0 else W + 150.0, randf_range(120.0, FLOOR_Y - 100.0))
	c.vel = Vector2(c.dir * 100.0, 0.0)
	c.phase = randf() * TAU
	c.col = Color.html("#5f739c")
	critters.append(c)


func spawn_jelly() -> void:
	var c := Critter.new()
	c.kind = "jelly"
	c.r = randf_range(26.0, 34.0)
	c.anchor = randf_range(120.0, W - 120.0)
	var down: bool = randf() < 0.6
	var spd: float = 45.0 + float(level) * 3.0
	c.pos = Vector2(c.anchor, -80.0 if down else H + 80.0)
	c.vel = Vector2(0.0, spd if down else -spd)
	c.phase = randf() * TAU
	c.col = Color(0.95, 0.45, 0.85, 0.75)
	critters.append(c)


func spawn_air() -> void:
	var c := Critter.new()
	c.kind = "air"
	c.r = 16.0
	c.anchor = randf_range(100.0, W - 100.0)
	c.pos = Vector2(c.anchor, FLOOR_Y + 20.0)
	c.vel = Vector2(0.0, -60.0)
	c.phase = randf() * TAU
	critters.append(c)


func update_critters(dt: float) -> void:
	var pr: float = player_radius()
	for c in critters:
		c.age += dt
		c.cd = maxf(0.0, c.cd - dt)
		var to: Vector2 = p_pos - c.pos
		var d: float = to.length()
		if c.kind == "small":
			update_small(c, dt, to, d, pr)
		elif c.kind == "pred":
			update_pred(c, dt, to, d, pr)
		elif c.kind == "jelly":
			update_jelly(c, dt, pr)
		elif c.kind == "air":
			update_air(c, dt, d, pr)
		if state != State.PLAY:
			return

	var i: int = critters.size() - 1
	while i >= 0:
		if critters[i].dead:
			critters.remove_at(i)
		i -= 1


func update_small(c: Critter, dt: float, to: Vector2, d: float, pr: float) -> void:
	c.phase += dt * 7.0
	var fear: float = 1.0
	if d < 190.0 and p_puff < 0.5:
		fear = 1.6
		c.anchor += -signf(to.y) * 70.0 * dt
	c.anchor = clampf(c.anchor, 60.0, FLOOR_Y - 40.0)
	c.pos.x += c.vel.x * fear * dt
	c.pos.y = c.anchor + sin(c.phase * 0.3) * 12.0
	if absf(c.vel.x) > 12.0:
		c.face = signf(c.vel.x)

	if p_puff < 0.35 and d < pr * 1.2 + c.r * 0.6:
		eat_fish(c)
		return
	if (c.vel.x > 0.0 and c.pos.x > W + 130.0) or (c.vel.x < 0.0 and c.pos.x < -130.0):
		c.dead = true


func eat_fish(c: Critter) -> void:
	c.dead = true
	eaten += 1
	var pts: int = int(c.r)
	add_score(pts)
	mouth_t = 0.25
	p_air = minf(1.0, p_air + 0.05)
	burst(c.pos, c.col, 7, 150.0)
	add_text(c.pos + Vector2(0.0, -24.0), "+%d" % pts, Color(1.0, 1.0, 0.6))
	var new_level: int = mini(10, 1 + int(eaten / 7.0))
	if new_level > level:
		level = new_level
		p_base_target = BASE0 + float(level - 1) * 2.2
		add_text(p_pos + Vector2(0.0, -80.0), "Naik level! Lv %d" % level, Color(0.7, 1.0, 0.8))


func update_pred(c: Critter, dt: float, to: Vector2, d: float, pr: float) -> void:
	c.phase += dt * 5.0
	if c.mode == "flee":
		c.vel = c.vel.move_toward(Vector2(c.dir * 460.0, 0.0), 1400.0 * dt)
		c.pos += c.vel * dt
		if absf(c.vel.x) > 12.0:
			c.face = signf(c.vel.x)
		if c.pos.x < -220.0 or c.pos.x > W + 220.0:
			c.dead = true
		return

	var speed: float = 120.0 + float(level) * 11.0
	var desired := Vector2(c.dir * 80.0, sin(c.phase * 0.4) * 30.0)
	if d < 480.0 and d > 0.001:
		var mul: float = 1.7 if d < 190.0 else 1.0
		desired = to / d * speed * mul
	c.vel = c.vel.lerp(desired, 1.0 - exp(-2.5 * dt))
	c.pos += c.vel * dt
	c.pos.y = clampf(c.pos.y, 40.0, FLOOR_Y)
	if absf(c.vel.x) > 12.0:
		c.face = signf(c.vel.x)
	if c.age > 4.0 and (c.pos.x < -220.0 or c.pos.x > W + 220.0):
		c.dead = true
		return

	if d < pr + c.r * 0.75:
		if p_puff > 0.7:
			if c.cd <= 0.0:
				c.mode = "flee"
				c.dir = 1.0 if c.pos.x >= p_pos.x else -1.0
				c.vel = Vector2(c.dir * 300.0, -80.0)
				c.cd = 1.0
				add_score(50 + 10 * level)
				add_text(c.pos + Vector2(0.0, -c.r * 1.4), "AUW!", Color(1.0, 0.7, 0.3))
				burst(c.pos, Color(1.0, 0.85, 0.5), 12, 220.0)
				shake = maxf(shake, 0.25)
		elif p_invuln <= 0.0:
			hurt(c.pos)
			if d > 0.001:
				c.vel = -to / d * 260.0
			c.cd = 0.8


func update_jelly(c: Critter, dt: float, pr: float) -> void:
	c.phase += dt * 2.0
	c.pos.y += c.vel.y * dt
	c.pos.x = c.anchor + sin(c.phase * 0.7) * 50.0
	if (c.vel.y > 0.0 and c.pos.y > H + 100.0) or (c.vel.y < 0.0 and c.pos.y < -100.0):
		c.dead = true
		return
	var hit_pos: Vector2 = c.pos + Vector2(0.0, c.r * 0.4)
	if p_invuln <= 0.0 and p_pos.distance_to(hit_pos) < pr * 0.8 + c.r * 0.85:
		hurt(c.pos)


func update_air(c: Critter, dt: float, d: float, pr: float) -> void:
	c.phase += dt * 3.0
	c.pos.y += c.vel.y * dt
	c.pos.x = c.anchor + sin(c.phase) * 18.0
	if c.pos.y < -40.0:
		c.dead = true
		return
	if d < pr + c.r:
		c.dead = true
		p_air = minf(1.0, p_air + 0.45)
		add_text(c.pos + Vector2(0.0, -24.0), "+Udara", Color(0.6, 0.95, 1.0))
		burst(c.pos, Color(0.7, 0.95, 1.0), 8, 120.0)


func hurt(from: Vector2) -> void:
	if state != State.PLAY:
		return
	lives -= 1
	p_invuln = 2.0
	shake = 0.4
	flash = 0.5
	var away: Vector2 = (p_pos - from).normalized()
	if away.is_zero_approx():
		away = Vector2.UP
	p_vel = away * 520.0
	burst(p_pos, Color(1.0, 0.35, 0.3), 14, 220.0)
	if lives <= 0:
		end_game()


# ---------------------------------------------------------------- efek

func burst(pos: Vector2, col: Color, n: int, spd: float = 160.0) -> void:
	for i in n:
		var p := Particle.new()
		p.pos = pos
		var a: float = randf() * TAU
		p.vel = Vector2(cos(a), sin(a)) * randf_range(spd * 0.3, spd)
		p.max_life = randf_range(0.4, 0.9)
		p.life = p.max_life
		p.col = col
		p.r = randf_range(2.0, 5.0)
		particles.append(p)


func add_text(pos: Vector2, s: String, col: Color) -> void:
	var ft := FloatText.new()
	ft.pos = pos
	ft.text = s
	ft.col = col
	texts.append(ft)


func update_effects(dt: float) -> void:
	var i: int = particles.size() - 1
	while i >= 0:
		var p: Particle = particles[i]
		p.life -= dt
		p.vel = p.vel * maxf(0.0, 1.0 - 2.5 * dt)
		p.vel.y -= 30.0 * dt
		p.pos += p.vel * dt
		if p.life <= 0.0:
			particles.remove_at(i)
		i -= 1
	i = texts.size() - 1
	while i >= 0:
		var ft: FloatText = texts[i]
		ft.life -= dt
		ft.pos.y -= 40.0 * dt
		if ft.life <= 0.0:
			texts.remove_at(i)
		i -= 1


# ---------------------------------------------------------------- gambar

func _draw() -> void:
	draw_background()
	match state:
		State.MENU:
			draw_particles_and_texts()
			draw_menu()
		State.PLAY:
			draw_game()
			draw_hud()
		State.PAUSED:
			draw_game()
			draw_hud()
			draw_rect(Rect2(-40.0, -40.0, W + 80.0, H + 80.0), Color(0.0, 0.05, 0.15, 0.55))
			txt_center("JEDA", 340.0, 84, Color.WHITE)
			txt_center("Tekan P / klik / tap di mana saja untuk lanjut", 400.0, 28, Color(0.85, 0.95, 1.0))
		State.OVER:
			draw_game()
			draw_hud()
			draw_game_over()


func ell_pts(c: Vector2, rx: float, ry: float, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func draw_ell(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_colored_polygon(ell_pts(c, rx, ry), col)


func txt(s: String, pos: Vector2, size: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(font, pos + Vector2(2.0, 3.0), s, align, width, size, Color(0.0, 0.0, 0.0, 0.45 * col.a))
	draw_string(font, pos, s, align, width, size, col)


func txt_center(s: String, y: float, size: int, col: Color) -> void:
	txt(s, Vector2(0.0, y), size, col, HORIZONTAL_ALIGNMENT_CENTER, W)


func sand_y(x: float) -> float:
	return FLOOR_Y + 30.0 + sin(x * 0.011) * 12.0 + sin(x * 0.027) * 6.0


func draw_background() -> void:
	var top := Color.html("#4cc9e8")
	var bot := Color.html("#0a4a7c")
	draw_polygon(
		PackedVector2Array([Vector2(-50.0, -50.0), Vector2(W + 50.0, -50.0), Vector2(W + 50.0, H + 50.0), Vector2(-50.0, H + 50.0)]),
		PackedColorArray([top, top, bot, bot])
	)
	for i in 5:
		var x0: float = 150.0 + float(i) * 260.0 + sin(t_total * 0.3 + float(i)) * 40.0
		draw_colored_polygon(
			PackedVector2Array([Vector2(x0, -50.0), Vector2(x0 + 90.0, -50.0), Vector2(x0 - 110.0, H * 0.8), Vector2(x0 - 200.0, H * 0.8)]),
			Color(1.0, 1.0, 1.0, 0.05)
		)
	for b in bg_bubbles:
		var bx: float = b.x + sin(t_total + b.y * 0.02) * 6.0
		draw_arc(Vector2(bx, b.y), b.z, 0.0, TAU, 12, Color(1.0, 1.0, 1.0, 0.25), 1.5)

	var sand := PackedVector2Array()
	var x: float = -50.0
	while x <= W + 50.0:
		sand.append(Vector2(x, sand_y(x)))
		x += 40.0
	sand.append(Vector2(W + 50.0, H + 50.0))
	sand.append(Vector2(-50.0, H + 50.0))
	draw_colored_polygon(sand, Color.html("#d8be7e"))

	for w in weeds:
		var base := Vector2(w.x, sand_y(w.x) + 4.0)
		var pts := PackedVector2Array()
		for j in 8:
			var f: float = float(j) / 7.0
			pts.append(base + Vector2(sin(t_total * 1.2 + w.z + f * 2.5) * 18.0 * f, -w.y * f))
		draw_polyline(pts, Color.from_hsv(0.33 + 0.05 * sin(w.z * 7.0), 0.6, 0.5), 6.0, true)
	draw_ell(Vector2(210.0, sand_y(210.0) + 6.0), 60.0, 28.0, Color(0.38, 0.42, 0.48))
	draw_ell(Vector2(960.0, sand_y(960.0) + 8.0), 80.0, 34.0, Color(0.33, 0.38, 0.45))


func draw_game() -> void:
	# urutan: gelembung udara, ubur-ubur, ikan kecil, pemangsa, pemain
	for c in critters:
		if c.kind == "air":
			draw_air(c)
	for c in critters:
		if c.kind == "jelly":
			draw_jelly(c)
	for c in critters:
		if c.kind == "small":
			draw_fish(c)
	for c in critters:
		if c.kind == "pred":
			draw_fish(c)
	if state != State.OVER:
		var blink: bool = p_invuln > 0.0 and int(t_total * 12.0) % 2 == 0
		if not blink:
			draw_puffer(p_pos, p_face, p_base, p_puff, p_wig, mouth_t > 0.0)
	draw_particles_and_texts()
	if flash > 0.0:
		draw_rect(Rect2(-40.0, -40.0, W + 80.0, H + 80.0), Color(1.0, 0.1, 0.1, flash * 0.5))


func draw_particles_and_texts() -> void:
	for p in particles:
		var a: float = clampf(p.life / p.max_life, 0.0, 1.0)
		draw_circle(p.pos, p.r, Color(p.col.r, p.col.g, p.col.b, a * p.col.a))
	for ft in texts:
		var a2: float = minf(1.0, ft.life * 2.0)
		txt(ft.text, ft.pos - Vector2(150.0, 0.0), 26, Color(ft.col.r, ft.col.g, ft.col.b, a2), HORIZONTAL_ALIGNMENT_CENTER, 300.0)


func draw_puffer(pos: Vector2, face: float, base: float, puff: float, wig: float, mouth_open: bool) -> void:
	# Sprite menghadap KIRI, jadi dibalik (scale x = -face) supaya moncong searah gerak.
	var w: float = lerpf(base * 2.5, base * 3.9, puff)
	var h: float = w * 0.87
	if mouth_open:
		w *= 1.1
		h *= 0.92
	var bob: float = sin(wig * 0.7) * base * 0.04
	var tilt: float = clampf(p_vel.y * 0.0015, -0.35, 0.35) * face if state != State.MENU else 0.0

	# duri yang mencuat di sekeliling badan saat kembung
	var sp: float = clampf((puff - 0.15) / 0.85, 0.0, 1.0)
	if sp > 0.0:
		draw_set_transform(pos + Vector2(0.0, bob), 0.0, Vector2.ONE)
		var n: int = 20
		var rx: float = w * 0.46
		var ry: float = h * 0.46
		var slen: float = (6.0 + base * 0.5) * sp
		var swid: float = 3.5 + base * 0.13
		for i in n:
			var a: float = TAU * float(i) / float(n) + 0.1
			var ca: float = cos(a)
			var sa: float = sin(a)
			var bp := Vector2(ca * rx, sa * ry)
			var nrm: Vector2 = Vector2(ca * ry, sa * rx).normalized()
			var perp: Vector2 = Vector2(-nrm.y, nrm.x) * swid
			var tip: Vector2 = bp + nrm * slen
			draw_colored_polygon(
				PackedVector2Array([bp - perp - nrm * 4.0, tip, bp + perp - nrm * 4.0]),
				Color(0.62, 0.78, 0.1)
			)

	draw_set_transform(pos + Vector2(0.0, bob), tilt, Vector2(-face, 1.0))
	if fish_tex != null:
		draw_texture_rect(fish_tex, Rect2(-w * 0.5, -h * 0.5, w, h), false)
	else:
		draw_ell(Vector2.ZERO, w * 0.5, h * 0.5, c_body)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_fish(c: Critter) -> void:
	var r: float = c.r
	var is_pred: bool = c.kind == "pred"
	var rx: float = r * 1.35
	var ry: float = r * 0.85
	var body: Color = c.col
	var dark: Color = body.darkened(0.35)
	var belly: Color = body.lightened(0.45)
	var tw: float = sin(c.phase * 1.4) * r * 0.35

	draw_set_transform(c.pos, 0.0, Vector2(c.face, 1.0))
	# ekor
	draw_colored_polygon(
		PackedVector2Array([Vector2(-rx * 0.8, 0.0), Vector2(-r * 1.85, -r * 0.7 + tw), Vector2(-r * 1.85, r * 0.7 + tw)]),
		dark
	)
	# sirip punggung
	var fin_h: float = 1.45 if is_pred else 1.15
	draw_colored_polygon(
		PackedVector2Array([Vector2(-r * 0.5, -ry * 0.8), Vector2(r * 0.3, -ry * 0.85), Vector2(-r * 0.2, -r * fin_h)]),
		dark
	)
	draw_ell(Vector2.ZERO, rx, ry, body)
	draw_ell(Vector2(0.0, ry * 0.3), rx * 0.85, ry * 0.55, belly)

	var ep := Vector2(rx * 0.55, -ry * 0.2)
	var er: float = r * 0.26
	if is_pred:
		draw_circle(ep, er, Color(1.0, 0.9, 0.3))
		draw_circle(ep + Vector2(er * 0.2, 0.0), er * 0.5, Color(0.1, 0.05, 0.1))
		draw_line(ep + Vector2(-er * 1.2, -er * 1.1), ep + Vector2(er * 1.0, -er * 0.2), Color(0.1, 0.1, 0.15), 3.5, true)
		# gigi
		var m0 := Vector2(rx * 0.98, ry * 0.15)
		var m1 := Vector2(rx * 0.35, ry * 0.3)
		draw_line(m0, m1, Color(0.1, 0.05, 0.1), 3.0, true)
		for k in 4:
			var f: float = (float(k) + 0.5) / 4.0
			var tp: Vector2 = m0.lerp(m1, f)
			draw_colored_polygon(
				PackedVector2Array([tp + Vector2(-r * 0.09, 0.0), tp + Vector2(r * 0.09, 0.0), tp + Vector2(0.0, r * 0.24)]),
				Color.WHITE
			)
	else:
		draw_circle(ep, er, Color.WHITE)
		draw_circle(ep + Vector2(er * 0.2, 0.0), er * 0.55, c_dark)
		draw_circle(Vector2(rx * 0.95, ry * 0.15), r * 0.07, dark)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if is_pred and c.mode == "normal" and p_puff < 0.7 and state == State.PLAY:
		if c.pos.distance_to(p_pos) < 280.0 and int(t_total * 6.0) % 2 == 0:
			txt("!", c.pos + Vector2(-9.0, -r * 1.5), 44, Color(1.0, 0.25, 0.2))


func draw_jelly(c: Critter) -> void:
	var ry: float = c.r * (0.85 + 0.1 * sin(c.phase * 3.0))
	# tentakel
	var tcol := Color(c.col.r, c.col.g, c.col.b, 0.6)
	for k in 5:
		var x0: float = -c.r * 0.7 + float(k) * c.r * 0.35
		var pts := PackedVector2Array()
		for j in 7:
			pts.append(c.pos + Vector2(x0 + sin(c.phase * 2.0 + float(j) * 0.9 + float(k)) * 5.0, float(j) * c.r * 0.28))
		draw_polyline(pts, tcol, 3.0, true)
	# glow + kubah
	draw_circle(c.pos, c.r * 1.4, Color(c.col.r, c.col.g, c.col.b, 0.12))
	var dome := PackedVector2Array()
	for i in 17:
		var a: float = PI + PI * float(i) / 16.0
		dome.append(c.pos + Vector2(cos(a) * c.r, sin(a) * ry))
	draw_colored_polygon(dome, c.col)
	draw_colored_polygon(ell_pts(c.pos + Vector2(-c.r * 0.3, -ry * 0.5), c.r * 0.25, ry * 0.15, 12), Color(1.0, 1.0, 1.0, 0.35))


func draw_air(c: Critter) -> void:
	var r: float = c.r * (1.0 + 0.06 * sin(c.phase * 2.0))
	draw_circle(c.pos, r, Color(0.6, 0.9, 1.0, 0.25))
	draw_arc(c.pos, r, 0.0, TAU, 24, Color(0.85, 0.97, 1.0, 0.9), 2.5, true)
	draw_arc(c.pos, r * 0.65, PI * 1.1, PI * 1.5, 8, Color.WHITE, 2.5, true)


func draw_heart(c: Vector2, col: Color) -> void:
	draw_circle(c + Vector2(-8.0, -4.0), 9.0, col)
	draw_circle(c + Vector2(8.0, -4.0), 9.0, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-16.5, 0.0), c + Vector2(16.5, 0.0), c + Vector2(0.0, 19.0)]), col)


func draw_hud() -> void:
	txt("Skor: %d" % score, Vector2(24.0, 44.0), 30, Color.WHITE)
	txt("Level %d" % level, Vector2(24.0, 78.0), 22, Color(0.85, 0.95, 1.0))

	# meter udara
	var bar := Rect2(24.0, 94.0, 220.0, 18.0)
	draw_rect(bar, Color(0.0, 0.0, 0.0, 0.35))
	var fill_col := Color(0.4, 0.9, 1.0)
	if p_exhausted:
		fill_col = Color(1.0, 0.35, 0.3) if int(t_total * 6.0) % 2 == 0 else Color(0.7, 0.2, 0.2)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * p_air, bar.size.y)), fill_col)
	draw_rect(bar, Color(1.0, 1.0, 1.0, 0.7), false, 2.0)
	txt("Udara", Vector2(254.0, 110.0), 18, Color(0.85, 0.95, 1.0))

	for i in 3:
		var hc := Color(1.0, 0.3, 0.4) if i < lives else Color(0.0, 0.0, 0.0, 0.35)
		draw_heart(Vector2(W - 40.0 - float(i) * 44.0, 42.0), hc)
	txt("Terbaik: %d" % best, Vector2(0.0, 92.0), 22, Color(1.0, 0.95, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, W - 24.0)

	if state == State.PLAY and game_time < 7.0:
		var hint: String = "Tahan tombol KEMBUNG untuk mengembang!" if show_touch_ui else "Tahan klik / Spasi untuk KEMBUNG!"
		txt_center(hint, H - 30.0, 26, Color(1.0, 1.0, 1.0, minf(1.0, (7.0 - game_time) * 1.0)))

	if show_touch_ui:
		# joystick analog (kiri bawah)
		draw_circle(JOY_C, JOY_R, Color(1.0, 1.0, 1.0, 0.12))
		draw_arc(JOY_C, JOY_R, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.6), 3.0, true)
		var knob: Vector2 = JOY_C + touch_vec
		draw_circle(knob, 42.0, Color(1.0, 1.0, 1.0, 0.45 if move_touch != -2 else 0.25))
		draw_arc(knob, 42.0, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, 0.8), 2.5, true)
		# tombol kembung (kanan bawah)
		var pressed: bool = not puff_touches.is_empty()
		draw_circle(PUFF_BTN, PUFF_R, Color(1.0, 1.0, 1.0, 0.35 if pressed else 0.18))
		draw_arc(PUFF_BTN, PUFF_R, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.7), 3.0, true)
		txt("KEMBUNG", PUFF_BTN + Vector2(-PUFF_R, 8.0), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, PUFF_R * 2.0)

	# tombol pause / lanjut (tengah atas)
	draw_circle(PAUSE_C, PAUSE_R, Color(0.0, 0.0, 0.0, 0.35))
	draw_arc(PAUSE_C, PAUSE_R, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, 0.8), 3.0, true)
	if state == State.PAUSED:
		draw_colored_polygon(
			PackedVector2Array([PAUSE_C + Vector2(-8.0, -14.0), PAUSE_C + Vector2(-8.0, 14.0), PAUSE_C + Vector2(14.0, 0.0)]),
			Color.WHITE
		)
	else:
		draw_rect(Rect2(PAUSE_C + Vector2(-11.0, -13.0), Vector2(7.0, 26.0)), Color.WHITE)
		draw_rect(Rect2(PAUSE_C + Vector2(4.0, -13.0), Vector2(7.0, 26.0)), Color.WHITE)


func draw_menu() -> void:
	var puff: float = clampf(sin(t_total * 1.2) * 1.4, 0.0, 1.0)
	draw_puffer(Vector2(W * 0.5, 360.0 + sin(t_total * 1.5) * 12.0), 1.0, 40.0, puff, t_total * 6.0, false)
	txt_center("IKAN BUNTAL", 190.0, 96, Color(1.0, 0.85, 0.3))
	txt_center("Makan ikan kecil  -  hindari ubur-ubur  -  kembung biar pemangsa kabur!", 252.0, 26, Color(0.9, 0.97, 1.0))
	txt_center("Gerak: kursor / WASD / panah / geser jari", 520.0, 24, Color.WHITE)
	txt_center("Kembung: tahan klik / Spasi / tombol KEMBUNG   (kembung = tidak bisa makan, udara terbatas)", 556.0, 24, Color.WHITE)
	if best > 0:
		txt_center("Rekor: %d" % best, 600.0, 24, Color(1.0, 0.95, 0.7))
	if int(t_total * 2.0) % 2 == 0:
		txt_center("Klik / Spasi / tap untuk mulai", 668.0, 32, Color(1.0, 1.0, 1.0))


func draw_game_over() -> void:
	draw_rect(Rect2(-40.0, -40.0, W + 80.0, H + 80.0), Color(0.0, 0.05, 0.15, 0.55))
	txt_center("GAME OVER", 250.0, 90, Color(1.0, 0.45, 0.4))
	txt_center("Skor: %d" % score, 330.0, 46, Color.WHITE)
	if new_best:
		txt_center("REKOR BARU!", 392.0, 36, Color(1.0, 0.9, 0.3))
	else:
		txt_center("Terbaik: %d" % best, 392.0, 30, Color(1.0, 0.95, 0.7))
	if over_delay <= 0.0 and int(t_total * 2.0) % 2 == 0:
		txt_center("Klik / Spasi / tap untuk main lagi", 480.0, 30, Color.WHITE)
