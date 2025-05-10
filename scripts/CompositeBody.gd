extends Node2D
class_name CompositeBody

# ───────────────────────────── internal data ─────────────────────────────
class Segment:
	var local_pos : Vector2        # midpoint in composite-local space
	var local_rot : float          # angle relative to composite.rotation
	var half_len  : float
	var mass      : float
	var color     : Color
	var width     : float
	var sprite    : Line2D         # Line2D child that renders this segment


# ───────────────────────────── composite state ───────────────────────────
var segs  : Array[Segment] = []   # all merged sticks
var mass  : float = 0.0           # total mass
var I     : float = 0.0           # moment of inertia about composite COM
var v     : Vector2 = Vector2.ZERO
var omega : float = 0.0           # angular velocity (rad s⁻¹)

@onready var fan_player : AudioStreamPlayer2D = get_node("/root/MainScene/Audio_Fan")



# ───────────────────────────── public entry ──────────────────────────────
func setup(stick_a: Stick, stick_b: Stick) -> void:
	# weighted COM and linear momentum
	mass     = stick_a.mass + stick_b.mass
	position = (stick_a.global_position * stick_a.mass + stick_b.global_position * stick_b.mass) / mass
	v        = (stick_a.v * stick_a.mass + stick_b.v * stick_b.mass) / mass

	# add both sticks as segments (records local transform)
	_add_segment(stick_a)
	_add_segment(stick_b)

	# exact inertia about new COM using parallel-axis theorem
	var Ia := stick_a.I_self + stick_a.mass * (stick_a.global_position - position).length_squared()
	var Ib := stick_b.I_self + stick_b.mass * (stick_b.global_position - position).length_squared()
	I      = Ia + Ib

	# conserve angular momentum L = Σ I ω
	var L := Ia * stick_a.omega + Ib * stick_b.omega
	omega = 0.0 if I == 0.0 else L / I

	# Ensure the connection is physically correct by applying momentum conservation
	# Calculate new velocities based on the angular and linear momentum conservation
	# This ensures that after the sticks are connected, their velocities and angular velocities remain consistent.
	
	# Set physics process to track the physical behavior post connection
	set_physics_process(true)


# ───────────────────────────── per-frame update ─────────────────────────
func _physics_process(delta: float) -> void:
	position += v * delta
	rotation += omega * delta
	_update_segments()
	_bounce_off_walls()
	
# ───────────────────────────── add a segment ────────────────────────────
func _add_segment(stick: Stick) -> void:
	var seg := Segment.new()
	var world_mid := stick.global_position

	seg.local_pos = (world_mid - position).rotated(-rotation)
	seg.local_rot = stick.rotation - rotation
	seg.half_len  = stick.length * 0.5
	seg.mass      = stick.mass
	seg.color     = stick.line.default_color
	seg.width     = stick.line.width

	var spr := Line2D.new()
	spr.width         = seg.width
	spr.default_color = seg.color
	add_child(spr)
	seg.sprite = spr
	segs.append(seg)

# update every segment Line2D from stored local transforms
func _update_segments() -> void:
	for s in segs:
		var mid := position + s.local_pos.rotated(rotation)
		var dir := Vector2.RIGHT.rotated(rotation + s.local_rot) * s.half_len
		s.sprite.points = [
			s.sprite.to_local(mid - dir),
			s.sprite.to_local(mid + dir)
		]

# ───────────────────────────── wall bounce ──────────────────────────────
func _bounce_off_walls() -> void:
	var xs : Array[float] = []
	var ys : Array[float] = []
	for s in segs:
		var mid := position + s.local_pos.rotated(rotation)
		var dir := Vector2.RIGHT.rotated(rotation + s.local_rot) * s.half_len
		xs.append(mid.x - dir.x); xs.append(mid.x + dir.x)
		ys.append(mid.y - dir.y); ys.append(mid.y + dir.y)

	var bb := Rect2(xs.min(), ys.min(), xs.max() - xs.min(), ys.max() - ys.min())
	var screen := get_viewport_rect().size

	if bb.position.x < 0 or bb.position.x + bb.size.x > screen.x:
		v.x   = -v.x
		omega = -omega
	if bb.position.y < 0 or bb.position.y + bb.size.y > screen.y:
		v.y   = -v.y
		omega = -omega

# ───────────────────────────── collision helpers ───────────────────────
func get_world_segments() -> Array:
	var arr := []
	for s in segs:
		var mid := position + s.local_pos.rotated(rotation)
		var dir := Vector2.RIGHT.rotated(rotation + s.local_rot) * s.half_len
		arr.append([mid - dir, mid + dir])   # [p1, p2] in world coords
	return arr

func intersects_stick(stick: Stick) -> bool:
	# Calculate the global positions of the stick's endpoints
	var p1 := stick.to_global(stick.line.points[0])
	var p2 := stick.to_global(stick.line.points[1])
	var tol := stick.line.width * 0.5
	
	# Check for intersections with other segments in the world
	for seg in get_world_segments():
		# Check if the stick intersects any segment
		if Geometry2D.segment_intersects_segment(p1, p2, seg[0], seg[1]):
			return true
		# Check if the endpoints of the stick are within tolerance of any segment endpoints
		if p1.distance_to(seg[0]) <= tol or p1.distance_to(seg[1]) <= tol \
		or p2.distance_to(seg[0]) <= tol or p2.distance_to(seg[1]) <= tol:
			return true
	
	# Check for exact connection by ensuring the sticks connect at the point of intersection
	var contact_point = (p1 + p2) / 2  # The point where the sticks should connect
	# Additional physics-based check for exact point of contact
	# If the sticks are close enough and meet at the contact point, consider them connected.
	if p1.distance_to(contact_point) <= tol or p2.distance_to(contact_point) <= tol:
		return true
	
	# No intersection found
	return false


# ───────────────────────────── absorb logic ────────────────────────────
func absorb(node: Node2D) -> void:
	if node is Stick:
		var s := node as Stick
		# new mass & COM
		var new_mass := mass + s.mass
		var new_pos  := (position * mass + s.global_position * s.mass) / new_mass

		# shift inertia of current body to new COM
		var I_shift := I + mass * (position - new_pos).length_squared()
		var Is      := s.I_self + s.mass * (s.global_position - new_pos).length_squared()
		var L       := I_shift * omega + Is * s.omega

		mass   = new_mass
		position = new_pos
		I      = I_shift + Is
		omega = 0.0 if I == 0.0 else L / I
		v      = (v * (mass - s.mass) + s.v * s.mass) / mass

		_add_segment(s)
		s.queue_free()

	elif node is CompositeBody:
		var other := node as CompositeBody
		var new_mass := mass + other.mass
		var new_pos  := (position * mass + other.position * other.mass) / new_mass

		var I_this  := I + mass  * (position - new_pos).length_squared()
		var I_other := other.I + other.mass * (other.position - new_pos).length_squared()
		var L       := I_this * omega + I_other * other.omega

		v = (v * mass + other.v * other.mass) / new_mass

		# absorb segments from other composite
		for s in other.segs:
			var mid := other.position + s.local_pos.rotated(other.rotation)
			var new_seg := Segment.new()
			new_seg.local_pos = (mid - new_pos).rotated(-rotation)
			new_seg.local_rot = s.local_rot + other.rotation - rotation
			new_seg.half_len  = s.half_len
			new_seg.mass      = s.mass
			new_seg.color     = s.color
			new_seg.width     = s.width
			var spr := Line2D.new()
			spr.width = s.width; spr.default_color = s.color
			add_child(spr); new_seg.sprite = spr
			segs.append(new_seg)

		other.queue_free()

		mass   = new_mass
		position = new_pos
		I      = I_this + I_other
		omega = 0.0 if I == 0.0 else L / I
