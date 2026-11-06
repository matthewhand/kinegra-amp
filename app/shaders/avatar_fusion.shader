shader_type spatial;
render_mode unshaded, blend_mix, cull_back;

// Shared per-avatar material: bounded GLES2 maths, no extra texture samples.
uniform vec4 style_color : hint_color = vec4(0.1,0.85,0.95,1.0);
uniform float scene_preset = 0.0;
uniform float surface_style = 0.0;
uniform float bass = 0.0;
uniform float mid = 0.0;
uniform float high = 0.0;
uniform float motion = 1.0;

// Original static surface motifs: no samples, loops, extra passes or retained
// images. Time drives only the existing audio-scene fusion below.
vec2 surface_finish(vec2 uv) {
    vec2 cell = fract(uv * vec2(6.0, 10.0));
    float ink = 0.0;
    float trim = 0.0;
    if (surface_style < 0.5) {
        // Circuit routes and terminal pads.
        float route = min(abs(cell.x - 0.22), abs(cell.y - 0.52));
        ink = 1.0 - smoothstep(0.025, 0.055, route);
        trim = 1.0 - smoothstep(0.07, 0.12, length(cell - vec2(0.22,0.52)));
    } else if (surface_style < 1.5) {
        // Broad brushed-chevron bands, independent of the circuit grid.
        float stripe = fract(uv.y * 10.0 + abs(uv.x - 0.5) * 6.0);
        ink = smoothstep(0.42,0.48,stripe) * (1.0-smoothstep(0.72,0.80,stripe));
        trim = smoothstep(0.91,0.96,fract(uv.y * 48.0));
    } else if (surface_style < 2.5) {
        // Faceted triangular ice plates.
        vec2 facet = fract(uv * vec2(5.0,8.0));
        ink = step(facet.x,facet.y) * 0.7;
        trim = 1.0-smoothstep(0.015,0.055,abs(facet.x-facet.y));
    } else if (surface_style < 3.5) {
        // Sparse cross-star inlays over diamond-weave fabric.
        vec2 star = abs(fract(uv * vec2(5.0,7.0))-0.5);
        trim = (1.0-smoothstep(0.025,0.055,min(star.x,star.y))) * (1.0-smoothstep(0.16,0.22,max(star.x,star.y)));
        ink = smoothstep(0.85,0.96,abs(sin((uv.x+uv.y)*42.0)*sin((uv.x-uv.y)*42.0)));
    } else {
        // Recessed rectangular armor panels and offset status slots.
        vec2 panel = abs(fract(uv * vec2(4.0,7.0))-0.5);
        ink = smoothstep(0.38,0.44,max(panel.x,panel.y));
        trim = (1.0-smoothstep(0.025,0.05,abs(panel.y-0.22))) * (1.0-smoothstep(0.13,0.20,panel.x));
    }
    return vec2(ink,trim);
}

void fragment() {
    float t = TIME * 0.65 * motion;
    vec2 p = UV * vec2(6.0, 9.0);
    float wisp = sin(p.y + sin(p.x * 1.4 - t) * 1.4 + t * 1.8);
    float fine = sin(p.x * 2.4 + p.y * 0.7 - t * 1.3);
    float flow = 0.5 + 0.5 * sin(wisp * 2.1 + fine + t);
    vec3 a = vec3(0.10,0.94,0.76);
    vec3 b = vec3(0.88,0.12,0.96);
    if (scene_preset > 0.5 && scene_preset < 1.5) {
        a = vec3(0.06,0.47,0.50);
        b = vec3(0.45,0.14,0.78);
    } else if (scene_preset > 1.5) {
        a = vec3(0.08,0.32,0.43);
        b = vec3(0.80,0.90,1.0);
    }
    vec3 scene_color = mix(a,b,flow);
    float energy=clamp(bass*0.6+mid*0.3+high*0.1,0.0,1.0);
    vec2 finish = surface_finish(UV);
    // Keep each costume identifiable under all scene presets and audio levels.
    vec3 base = mix(style_color.rgb, scene_color, 0.22 + energy*0.16);
    base = base * mix(0.52,1.05,finish.x) + vec3(0.28)*finish.y;
    float edge=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.0);
    ALBEDO=base*(0.58+flow*0.25);
    EMISSION=scene_color*(0.10+edge*0.28+energy*0.40)+style_color.rgb*finish.y*0.55;
    ALPHA=clamp(0.88+edge*0.1,0.0,1.0);
}
