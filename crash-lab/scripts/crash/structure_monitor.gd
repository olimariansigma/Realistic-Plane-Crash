class_name StructureMonitor
extends RefCounted
## Computes the load carried by every structural joint, every physics tick,
## and reports the joints whose load exceeds the part's break threshold.
##
## Godot's Jolt integration does not expose the impulse a joint applied, so
## the load is recovered by inverse dynamics, which is exact for a tree of
## rigid bodies:
##
##   For body k, Newton gives  m a = F_applied + m g + F_contact + F_joints.
##   Define the residual       D_k = m a - F_applied - m g
##                                 = F_joints(k) + F_contact(k).
##   Sum D over the subtree outboard of a joint: every joint inside the
##   subtree appears twice with opposite sign and cancels, leaving
##       S = F_joint + C_sub        (C_sub: contact force on the subtree).
##   The same holds for moments, taken about one common reference point.
##
## `a` comes from the velocity change over the last step and F_applied is
## known exactly because all game forces go through AircraftPart.push_*.
## Contacts are the only unknown, and they are handled in three cases:
##   - subtree not touching anything:        F_joint = S                (exact)
##   - only the subtree is touching:         F_joint = S - T            (exact)
##     where T is the whole assembly's residual sum, which equals the total
##     contact force when nothing else is in contact;
##   - both sides touching:  Jolt's estimated contact impulses are used on
##     whichever side gives the smaller load (conservative: a joint is never
##     broken by an over-estimated contact).
##
## The joint load is compared with the part's `break_force` (N) and
## `break_torque` (N m, about the joint anchor). A short low-pass filter
## rejects single-step solver noise without hiding real impacts, which
## exceed the thresholds by a wide margin.

const GRAVITY := Vector3(0.0, -9.80665, 0.0)
## Weight of the newest sample in the load filter.
const FILTER := 0.5

var parts: Array[AircraftPart]
## Filtered load / threshold per joint, indexed by the child part. >= 1 breaks.
var load_ratio: PackedFloat32Array
## Highest filtered ratio seen so far, for telemetry and tuning.
var peak_ratio: PackedFloat32Array
## Latest unfiltered joint force (N) and moment about the anchor (N m).
var joint_force: PackedFloat32Array
var joint_torque: PackedFloat32Array
## Indices of joints that exceeded their threshold in the last update().
var broken: PackedInt32Array
## Set false to observe loads without breaking anything.
var enabled: bool = true

var _count: int = 0
var _sub_force: PackedVector3Array
var _sub_moment: PackedVector3Array
var _sub_contact: PackedVector3Array
var _sub_contact_moment: PackedVector3Array
var _sub_contacts: PackedInt32Array


func setup(aircraft_parts: Array[AircraftPart]) -> void:
	parts = aircraft_parts
	_count = parts.size()
	load_ratio.resize(_count)
	peak_ratio.resize(_count)
	joint_force.resize(_count)
	joint_torque.resize(_count)
	_sub_force.resize(_count)
	_sub_moment.resize(_count)
	_sub_contact.resize(_count)
	_sub_contact_moment.resize(_count)
	_sub_contacts.resize(_count)
	load_ratio.fill(0.0)
	peak_ratio.fill(0.0)


## Call once per physics tick after every part's begin_tick() and before the
## tick's forces are applied (ext_force still holds last tick's forces).
func update(dt: float) -> void:
	broken.clear()
	if dt <= 0.0:
		return
	var inv_dt := 1.0 / dt
	var reference := parts[0].xf.origin

	# 1. Per-body residuals and contact estimates for the step just simulated.
	for i: int in _count:
		var p := parts[i]
		var ang_mom := p.angular_momentum()
		var r := p.xf.origin - reference
		if p.has_prev:
			var d := (p.lin_vel - p.prev_lin_vel) * (p.mass * inv_dt) - p.ext_force - GRAVITY * p.mass
			_sub_force[i] = d
			_sub_moment[i] = (ang_mom - p.prev_ang_mom) * inv_dt - p.ext_torque + r.cross(d)
		else:
			_sub_force[i] = Vector3.ZERO
			_sub_moment[i] = Vector3.ZERO
			p.has_prev = true
		p.prev_lin_vel = p.lin_vel
		p.prev_ang_mom = ang_mom
		if p.contact_count > 0 and not p.sleeping:
			var c := p.contact_impulse * inv_dt
			_sub_contact[i] = c
			_sub_contact_moment[i] = p.contact_torque_impulse * inv_dt + r.cross(c)
			_sub_contacts[i] = p.contact_count
		else:
			_sub_contact[i] = Vector3.ZERO
			_sub_contact_moment[i] = Vector3.ZERO
			_sub_contacts[i] = 0

	# 2. Fold children into parents. Parents precede children in the array, so
	#    one backwards pass accumulates every subtree.
	for i: int in range(_count - 1, 0, -1):
		var p := parts[i]
		if p.joint == null:
			continue
		var parent := p.parent_index
		_sub_force[parent] += _sub_force[i]
		_sub_moment[parent] += _sub_moment[i]
		_sub_contact[parent] += _sub_contact[i]
		_sub_contact_moment[parent] += _sub_contact_moment[i]
		_sub_contacts[parent] += _sub_contacts[i]

	# 3. Joint loads.
	for i: int in range(1, _count):
		var p := parts[i]
		if p.joint == null:
			continue
		var root := p.assembly_root
		var force := _sub_force[i]
		var moment := _sub_moment[i]
		var touching := _sub_contacts[i]
		var touching_rest := _sub_contacts[root] - touching
		var anchor_offset := p.xf * p.anchor_local - reference
		var def := p.def
		var f_mag: float
		var m_mag: float
		if touching == 0:
			f_mag = force.length()
			m_mag = (moment - anchor_offset.cross(force)).length()
		elif touching_rest == 0:
			force -= _sub_force[root]
			moment -= _sub_moment[root]
			f_mag = force.length()
			m_mag = (moment - anchor_offset.cross(force)).length()
		else:
			var fa := force - _sub_contact[i]
			var ma := moment - _sub_contact_moment[i]
			var fb := force - _sub_force[root] + (_sub_contact[root] - _sub_contact[i])
			var mb := moment - _sub_moment[root] + (_sub_contact_moment[root] - _sub_contact_moment[i])
			var fa_mag := fa.length()
			var ma_mag := (ma - anchor_offset.cross(fa)).length()
			var fb_mag := fb.length()
			var mb_mag := (mb - anchor_offset.cross(fb)).length()
			var ra := maxf(fa_mag / def.break_force, ma_mag / def.break_torque)
			var rb := maxf(fb_mag / def.break_force, mb_mag / def.break_torque)
			if ra <= rb:
				f_mag = fa_mag
				m_mag = ma_mag
			else:
				f_mag = fb_mag
				m_mag = mb_mag
		joint_force[i] = f_mag
		joint_torque[i] = m_mag
		var ratio := maxf(f_mag / def.break_force, m_mag / def.break_torque)
		var filtered := lerpf(load_ratio[i], ratio, FILTER)
		load_ratio[i] = filtered
		if filtered > peak_ratio[i]:
			peak_ratio[i] = filtered
		if enabled and filtered >= 1.0:
			broken.append(i)
