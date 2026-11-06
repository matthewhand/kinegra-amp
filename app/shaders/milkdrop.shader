shader_type canvas_item;
render_mode unshaded;

// Original bounded GLES2 scenes. The three existing preset IDs are retained.
uniform vec4 bands_0 = vec4(0.0);
uniform vec4 bands_1 = vec4(0.0);
uniform vec4 bands_2 = vec4(0.0);
uniform vec4 bands_3 = vec4(0.0);
uniform float reactive = 0.0;
uniform float visual_preset = 0.0;
uniform float motion = 1.0;
uniform sampler2D original_backdrop;
uniform bool has_backdrop = false;
uniform float viewport_aspect = 1.777778;

void fragment() {
    vec2 uv = UV;
    float aspect = max(0.25, viewport_aspect);
    vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0) / min(aspect, 1.0);
    float bass = clamp((bands_0.x + bands_0.y + bands_0.z) / 3.0, 0.0, 1.0);
    float mid = clamp((bands_1.x + bands_1.y + bands_1.z) / 3.0, 0.0, 1.0);
    float high = clamp((bands_2.x + bands_2.y + bands_3.x) / 3.0, 0.0, 1.0);
    float energy = smoothstep(0.005, 0.30, bass * 2.0 + mid + high * 0.7);
    // Silence has no moving/reactive geometry. Reduced motion also freezes
    // phase; the amplitude still reflects real FFT values, never a fake beat.
    float t = TIME * clamp(motion, 0.0, 1.0) * step(0.001, energy) * 0.35;
    vec3 col = mix(vec3(0.008, 0.014, 0.030), vec3(0.025, 0.035, 0.065), uv.y);
    // Legacy backdrop bindings remain compatible; the scenes use no image samples.
    if (visual_preset < 0.5) {
        // HORIZON GRID: folding terrain and three independently driven ridges.
        float horizon = 0.43;
        if (uv.y > horizon) {
            float depth = (uv.y - horizon) / (1.0 - horizon);
            float folded = p.x + sin(depth * 7.0 + t) * bass * 0.16;
            float gx = abs(fract(folded * 3.0 / (depth + 0.18) + 0.5) - 0.5);
            float gz = abs(fract(1.6 / (depth + 0.12) - t * 0.20) - 0.5);
            float mesh = (1.0 - smoothstep(0.012, 0.035, gx)) + (1.0 - smoothstep(0.012, 0.035, gz));
            col += mesh * mix(vec3(0.02, 0.55, 0.65), vec3(0.48, 0.08, 0.55), uv.x) * (0.035 + energy * 0.22) * depth;
        }
        for (int i = 0; i < 3; i++) {
            float layer = float(i);
            float amplitude = i == 0 ? bass : (i == 1 ? mid : high);
            float fold_a = abs(fract(p.x * (0.80 + layer * 0.28) + t * 0.045 + layer * 0.18) - 0.5) * 2.0;
            float fold_b = abs(fract(p.x * (1.70 + layer * 0.35) - t * 0.025 + layer * 0.31) - 0.5) * 2.0;
            float ridge = 0.43 - layer * 0.035 - fold_a * (0.028 + amplitude * 0.18) - fold_b * amplitude * 0.065;
            float line = 1.0 - smoothstep(0.0015, 0.014, abs(uv.y - ridge));
            col += line * mix(vec3(0.06, 0.72, 0.83), vec3(0.74, 0.11, 0.50), layer * 0.5) * (0.035 + energy * (0.40 + amplitude));
        }
    } else if (visual_preset < 1.5) {
        // NEBULA FLOW: broad luminous aurora curtains, not a shared overlay.
        for (int i = 0; i < 3; i++) {
            float layer = float(i);
            float center = 0.34 + layer * 0.12 + sin(p.x * (3.4 + layer) + t * 0.45 + layer * 1.8) * (0.05 + mid * 0.12);
            center += sin(p.x * 8.0 - t * 0.22 + layer) * high * 0.055;
            float width = 0.025 + bass * 0.065 + layer * 0.006;
            float curtain = max(0.0, 1.0 - abs(uv.y - center) / width);
            float strands = 0.65 + 0.35 * sin(p.x * (46.0 + layer * 11.0) + t * 0.3);
            float tail = (1.0 - smoothstep(0.0, width * 4.0, uv.y - center)) * step(center, uv.y);
            vec3 aurora = mix(vec3(0.06, 0.85, 0.52), vec3(0.42, 0.16, 0.88), layer * 0.5);
            col += aurora * (curtain * curtain * strands + tail * 0.11) * energy * (0.35 + mid * 0.8);
        }
    } else {
        // STARFIELD: tilted orbital braids and sparse real-audio-lit stars.
        vec2 star_grid = uv * vec2(72.0 * aspect, 72.0);
        vec2 cell = floor(star_grid);
        float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
        float star = step(0.990, seed) * (1.0 - smoothstep(0.06, 0.24, length(fract(star_grid) - vec2(0.5))));
        col += star * vec3(0.45, 0.65, 0.85) * energy * (0.10 + high * 0.65);
        for (int i = 0; i < 3; i++) {
            float layer = float(i);
            float angle = layer * 1.05 + t * (0.12 + layer * 0.035);
            mat2 rotation = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));
            vec2 q = rotation * p;
            vec2 ellipse = q * vec2(0.85, 1.30);
            float radius = 0.23 + layer * 0.075 + bass * 0.035;
            float braid = 1.0 - smoothstep(0.002, 0.010 + high * 0.012, abs(length(ellipse) - radius));
            float travel = 0.45 + 0.55 * sin(q.x * 13.0 + q.y * 8.0 + t * (1.0 + layer * 0.2));
            vec3 orbit = mix(vec3(0.10, 0.58, 0.95), vec3(0.95, 0.24, 0.36), layer * 0.5);
            col += orbit * braid * travel * energy * (0.35 + mid);
        }
    }
    COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
