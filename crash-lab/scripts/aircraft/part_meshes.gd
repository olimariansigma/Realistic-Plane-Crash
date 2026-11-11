class_name PartMeshes
extends RefCounted
## Everything MeshFactory generates for one part.

var pieces: Array[SkinPiece] = []
## Internal structure, revealed where skin is missing.
var core: ArrayMesh
## Engines show their core through the intake even when intact.
var core_always_visible: bool = false
## Single merged mesh for the far LOD.
var far: ArrayMesh
## Landing gear only.
var strut: ArrayMesh
var wheels: ArrayMesh
