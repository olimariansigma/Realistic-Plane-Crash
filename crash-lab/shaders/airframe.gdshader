shader_type spatial;
render_mode cull_disabled;
// Normal variant (no cutaway clip, so the GPU keeps early depth testing).
#include "res://shaders/airframe.gdshaderinc"
