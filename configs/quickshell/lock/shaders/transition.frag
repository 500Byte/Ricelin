#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float maskP;
    vec2 res;
    vec2 pillCenter;
    float pillHW;
    float pillHH;
    float soften;
    float glow;
    vec3 accent;
    float chromaStrength;
    float burstIntensity;
    vec3 burstColor;
};
layout(binding = 1) uniform sampler2D source;

float sdStadium(vec2 p) {
    vec2 d = abs(p) - vec2(pillHW - pillHH, 0.0);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - pillHH;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * res - pillCenter;

    float d = sdStadium(p);

    float ripple = sin(length(p) * 0.08 - maskP * 25.132)
                 * 4.0 * max(0.0, 1.0 - maskP * 2.0);

    float maxDist = max(res.x, res.y) * 1.2;
    float edgeDist = maskP * maxDist + ripple;

    float blend = 1.0 - smoothstep(edgeDist - soften, edgeDist + soften, d);
    float alpha = 1.0 - blend;

    vec2 dir = p == vec2(0.0) ? vec2(1.0, 0.0) : normalize(p);
    float edgeFalloff = exp(-abs(d - edgeDist) / max(soften * 0.4, 1.0));
    vec2 chromaOff = dir * edgeFalloff * chromaStrength / res;

    float r = texture(source, uv + chromaOff).r;
    float gt = texture(source, uv).g;
    float b = texture(source, uv - chromaOff).b;

    vec3 col = vec3(r, gt, b);

    float burst = exp(-pow((maskP - 0.9) * 18.0, 2.0));
    float burstGate = smoothstep(0.3, 0.8, alpha);
    vec3 flash = burstColor * burst * burstIntensity * burstGate;

    float ge = exp(-abs(d - edgeDist) / max(soften * 0.3, 1.0));
    vec3 glowCol = accent * ge * glow;
    alpha += ge * glow * 0.2;

    fragColor = vec4(col * alpha + glowCol + flash,
                     clamp(alpha + flash.r * 0.3, 0.0, 1.0)) * qt_Opacity;
}