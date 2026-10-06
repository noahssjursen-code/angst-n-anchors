shader_type spatial;
render_mode diffuse_burley, cull_disabled;

#define OCEAN_CASCADE_COUNT 2
#define OCEAN_FOAM 0
#define OCEAN_WAKE 0
#include "res://resources/shaders/ocean_lod_surface.gdshaderinc"
