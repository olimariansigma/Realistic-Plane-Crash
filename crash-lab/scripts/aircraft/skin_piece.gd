class_name SkinPiece
extends RefCounted
## One detachable piece of a part's skin: a fuselage panel, a wing box
## segment, a control surface, a cowl half. Shared between every instance of
## the aircraft type; per-aircraft state (attached or not) lives on the part.

enum Surface { NONE, AILERON, ELEVATOR, RUDDER, FLAP }

var mesh: ArrayMesh
## Centroid and bounding size in the part's local frame.
var center: Vector3
var size: Vector3
## Where the mesh's own origin sits in the part frame (the hinge line for
## control surfaces, identity otherwise).
var xform := Transform3D.IDENTITY
var mass: float = 10.0
var control: Surface = Surface.NONE
## Hinge axis (part-local unit vector) and travel for moving surfaces.
var hinge: Vector3
var deflect_max: float = 0.0
## +1 right of the centreline, -1 left: ailerons move opposite ways.
var side: float = 1.0
## Internal structure (frames and stringers of a fuselage bay, spar and rib
## segments of a wing box) rather than skin. Structure is drawn with the
## interior material, does not count as skin for lift, and can only be torn
## out once the skin over it (`cover`) has gone.
var structure: bool = false
## Index of the skin piece covering this one, or -1.
var cover: int = -1
