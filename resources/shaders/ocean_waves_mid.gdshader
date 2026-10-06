shader_type spatial;
render_mode diffuse_burley, cull_disabled;

#define OCEAN_CASCADE_COUNT 3
#define OCEAN_FOAM 1
#define OCEAN_WAKE 1
#include "res://resources/shaders/ocean_lod_surface.gdshaderinc"
