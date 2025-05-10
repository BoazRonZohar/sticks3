extends Node2D

const StickScene      := preload("res://scenes/stick.tscn")
const CompositeScene  := preload("res://scenes/composite_body.tscn")

@onready var sticks_layer  : Node2D = $Sticks
@onready var comps_layer   : Node2D = $CompositeBodies
@onready var audio_hit     : AudioStreamPlayer2D = $Audio_Collision
@onready var audio_merge   : AudioStreamPlayer2D = $Audio_Merge
@onready var audio_fan : AudioStreamPlayer2D = $Audio_Fan

# ────────────────────────────────────────────
func _ready() -> void:
	_spawn_stick(get_viewport_rect().size * 0.5)   # one stick at centre

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_spawn_stick(event.position)

func _physics_process(delta):
	_update_sticks(delta)
	_handle_collisions()
	_update_fan_sound()

func _update_fan_sound() -> void:
	var fast_found : bool = false

	# 1) scan all sticks
	for s in sticks_layer.get_children():
		if abs(s.omega) > Stick.OMEGA_SOUND_THR:
			fast_found = true
			break

	# 2) if none found among sticks, scan composites
	if not fast_found:
		for c in comps_layer.get_children():
			if abs(c.omega) > Stick.OMEGA_SOUND_THR:
				fast_found = true
				break

	# 3) play/stop only once per frame
	if fast_found:
		if not audio_fan.playing:
			audio_fan.play()
	else:
		if audio_fan.playing:
			audio_fan.stop()

# ────────────────────────────────────────────
func _spawn_stick(pos: Vector2) -> void:
	var s: Stick = StickScene.instantiate()  # Instantiate the Stick scene
	s.position = pos  # Set the position of the stick in the scene
	
	# Add the stick to the scene
	sticks_layer.add_child(s)
	
	# Play sound for confirmation of spawning
	audio_hit.play()  # Simple click-confirmation sound

# ────────────────────────────────────────────
func _update_sticks(delta: float) -> void:
	for s: Stick in sticks_layer.get_children():
		s.integrate_motion(delta)

# ────────────────────────────────────────────
func _merge_stick_stick(a: Stick, b: Stick) -> void:
	# Instantiate the composite body (CompositeBody)
	var comp := CompositeScene.instantiate() as CompositeBody
	comps_layer.add_child(comp)
	
	# Set the composite body position to the midpoint of the two sticks
	comp.position = (a.global_position + b.global_position) * 0.5
	
	# Set up the composite body with the two sticks
	comp.setup(a, b)
	
	# Remove the individual sticks from the scene (since they're merged into the composite body)
	a.queue_free()
	b.queue_free()
	
	# Play sound for confirmation of the merge
	audio_merge.play()

	# Additional logic for momentum and angular velocity preservation
	# Ensure that after merging, the combined body preserves the linear and angular momentum
	# from the original sticks (preserving their speeds and rotations).

# ────────────────────────────────────────────
func _handle_collisions() -> void:
	# 1) stick–stick  (same as before)
	var sticks := sticks_layer.get_children()
	for i in range(sticks.size()):
		for j in range(i + 1, sticks.size()):
			var a: Stick = sticks[i]
			var b: Stick = sticks[j]
			if a.intersects_with(b):
				_merge_stick_stick(a, b)
				return    # only one merge per physics tick

	# 2) stick → composite
	for s: Stick in sticks_layer.get_children():
		for c: CompositeBody in comps_layer.get_children():
			if c.intersects_stick(s):
				c.absorb(s)
				s.queue_free()
				audio_merge.play()
				return

	# 3) composite → composite
	var comps := comps_layer.get_children()
	for i in range(comps.size()):
		for j in range(i + 1, comps.size()):
			var ca: CompositeBody = comps[i]
			var cb: CompositeBody = comps[j]
			# quick test via segment lists
			for segA in ca.get_world_segments():
				for segB in cb.get_world_segments():
					if Geometry2D.segment_intersects_segment(segA[0], segA[1], segB[0], segB[1]):
						ca.absorb(cb)
						audio_merge.play()
						return

# ────────────────────────────────────────────
func _merge(a: Stick, b: Stick) -> void:
	var comp := CompositeScene.instantiate() as CompositeBody
	comps_layer.add_child(comp)
	comp.setup(a, b)

	a.queue_free()
	b.queue_free()
	audio_merge.play()
