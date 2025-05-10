extends Node2D
class_name Stick

# tunables
const MIN_LEN       : float = 5.0
const MAX_LEN       : float = 30.0
const MIN_OMEGA     : float = -30
const MAX_OMEGA     : float = 30
const THICKNESS     : float = 4.0
const MASS_PER_PX   : float = 0.01       # 1 px == 0.01 mass-units
const MIN_SPEED     : float =  80.0      #  (pixels / s)
const MAX_SPEED     : float = 260.0      # 
const OMEGA_SOUND_THR : float = 20      # play fan above |ω| > this

var length : float                # chosen per-instance
var mass   : float                # length × density
var I_self : float              # 1/12 m L² about the stick’s own centre
var v      : Vector2 = Vector2.ZERO
var omega  : float  = 0.0
var bounds : Vector2

@onready var line : Line2D = $Line
@onready var fan_player : AudioStreamPlayer2D = get_node("/root/MainScene/Audio_Fan")


# ─────────────────────────────────────────────
func _ready() -> void:
	length = randf_range(MIN_LEN, MAX_LEN)
	mass   = length * MASS_PER_PX
	I_self = mass * pow(length, 2) / 12.0 
	
	# random colour & motion
	line.default_color = Color.from_hsv(randf(), 1.0, 1.0)
	var speed := randf_range(MIN_SPEED, MAX_SPEED)
	var angle := randf_range(0, TAU)
	v = Vector2.RIGHT.rotated(angle) * speed

	omega  = randf_range(MIN_OMEGA,MAX_OMEGA)

	bounds = get_viewport_rect().size
	_update_line()

func integrate_motion(delta: float) -> void:
	# Update position based on linear velocity
	position += v * delta
	
	# Update rotation based on angular velocity
	rotation += omega * delta
	
	# Update the line rendering
	_update_line()
	
	# Handle bouncing when hitting the walls
	_bounce()
	
	# New logic to preserve momentum after the connection
	# After connecting sticks, ensure their linear velocity (v) and angular velocity (omega) are preserved correctly.
	# We can use the `v` and `omega` to adjust the motion properly post-connection.

func _update_line() -> void:
	var h := length * 0.5
	line.width  = THICKNESS
	line.points = [ Vector2(-h,0), Vector2(h,0) ]   # local space only

func _bounce() -> void:
	var p1 := to_global(line.points[0])
	var p2 := to_global(line.points[1])
	var min_x = min(p1.x,p2.x); var max_x = max(p1.x,p2.x)
	var min_y = min(p1.y,p2.y); var max_y = max(p1.y,p2.y)

	if min_x < 0 or max_x > bounds.x:
		v.x = -v.x; omega = -omega
	if min_y < 0 or max_y > bounds.y:
		v.y = -v.y; omega = -omega

# ─────────────────────────────────────────────
func intersects_with(other: Stick) -> bool:
	var p1 := to_global(line.points[0])
	var p2 := to_global(line.points[1])
	var ol := other.line
	var q1 := other.to_global(ol.points[0])
	var q2 := other.to_global(ol.points[1])
	
	# If the segments intersect, return true
	if Geometry2D.segment_intersects_segment(p1, p2, q1, q2):
		return true
	
	# Check if the endpoints are within tolerance of each other
	var tolerance := THICKNESS * 0.5  # Changed variable name from tol to tolerance
	if p1.distance_to(q1) <= tolerance or p1.distance_to(q2) <= tolerance \
		or p2.distance_to(q1) <= tolerance or p2.distance_to(q2) <= tolerance:
		
		# If the sticks are close enough, connect them
		# This part ensures the connection happens at the right point
		# You can perform additional momentum handling logic here if needed
		
		return true
		
	# Return false if no intersection is found
	return false

		
