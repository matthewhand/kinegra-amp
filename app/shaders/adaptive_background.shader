shader_type canvas_item;
render_mode unshaded;
// Light versions preserve each scene's form with no loops or texture reads.
uniform vec4 bands_0 = vec4(0.0);
uniform float reactive = 0.0;
uniform float motion = 1.0;
uniform float viewport_aspect = 1.777778;
uniform float visual_preset = 0.0;
void fragment() {
    float bass = clamp((bands_0.x + bands_0.y + bands_0.z) / 3.0, 0.0, 1.0);
    float energy = smoothstep(0.005, 0.25, bass + clamp(reactive, 0.0, 1.0));
    float t = TIME * clamp(motion, 0.0, 1.0) * step(0.001, energy) * 0.25;
    float aspect = max(0.25, viewport_aspect);
    vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0) / min(aspect, 1.0);
    vec3 col = mix(vec3(0.008, 0.014, 0.030), vec3(0.025, 0.035, 0.065), UV.y);
    if (visual_preset < 0.5) {
        float fold = abs(fract(p.x * 1.1 + t * 0.045) - 0.5) * 2.0;
        float ridge = 0.43 - fold * (0.03 + bass * 0.18);
        float line = 1.0 - smoothstep(0.002, 0.015, abs(UV.y - ridge));
        col += vec3(0.06, 0.65, 0.78) * line * (0.03 + energy * 0.5);
    } else if (visual_preset < 1.5) {
        float center = 0.48 + sin(p.x * 4.0 + t) * (0.05 + bass * 0.16);
        float curtain = max(0.0, 1.0 - abs(UV.y - center) / (0.035 + bass * 0.07));
        col += mix(vec3(0.05, 0.70, 0.45), vec3(0.38, 0.12, 0.80), UV.x) * curtain * curtain * energy * 0.7;
    } else {
        float ellipse = length(p * vec2(0.9, 1.3));
        float ring = 1.0 - smoothstep(0.003, 0.014, abs(ellipse - (0.28 + bass * 0.06)));
        float trail = 0.55 + 0.45 * sin(p.x * 10.0 + p.y * 8.0 + t);
        col += vec3(0.32, 0.42, 0.85) * ring * trail * energy * 0.8;
    }
    COLOR = vec4(col, 1.0);
}
