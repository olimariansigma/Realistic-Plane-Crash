shader_type spatial;
render_mode cull_disabled;
// Cutaway variant: swapped onto the shared material only while the cutaway
// is shown, because `discard` disables early depth testing on mobile GPUs.
#define CUTAWAY
#include "res://shaders/airframe.gdshaderinc"
