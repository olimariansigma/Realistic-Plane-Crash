class_name SeatBlockDef
extends Resource
## A rectangular block of seats in one fuselage part.

@export var label: String = "Economy"
## Fuselage part the seats are bolted to.
@export var part: StringName
## First row number for seat labels ("12A").
@export var first_row: int = 1
@export var rows: int = 10
## Z of the first row (aircraft frame); rows continue aft (+Z).
@export var z_start: float = 0.0
@export var pitch: float = 0.8
## X offset of each seat across the row, left to right.
@export var abreast: PackedFloat32Array
## Height of the cabin floor (aircraft frame Y).
@export var floor_y: float = -0.6
## True for flight-deck seats.
@export var is_crew: bool = false
