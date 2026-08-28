shader_type canvas_item;

// Define the UV.x coordinates for the 4 corners of the trapezoid.
// 0.0 is the left edge, 1.0 is the right edge.
uniform float top_left = 0.0;
uniform float top_right = 1.0;
uniform float bottom_left = 0.0;
uniform float bottom_right = 1.0;

void fragment() {
	// Interpolate the left and right edges based on the vertical position (UV.y)
	float min_x = mix(top_left, bottom_left, UV.y);
	float max_x = mix(top_right, bottom_right, UV.y);
	
	if (UV.x < min_x || UV.x > max_x) {
		COLOR.a = 0.0;
	}
}
