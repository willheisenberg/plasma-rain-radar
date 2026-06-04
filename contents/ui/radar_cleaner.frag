#version 440

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

layout(binding = 1) uniform sampler2D source;

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 color = texture(source, qt_TexCoord0);
    
    // 1. Gray background: R ≈ G ≈ B (all within 0.03 of each other), any alpha > 0.
    bool is_gray = (abs(color.r - color.g) <= 0.03 && 
                    abs(color.r - color.b) <= 0.03 && 
                    abs(color.g - color.b) <= 0.03) && (color.a > 0.0);
    
    // 2. Pink/magenta border detection.
    //    Border pixels: R ≈ B with G much lower (pure magenta + anti-aliased blends).
    //    Closest rain color: (204,0,152) has abs(R-B) = 0.204, so 0.19 is safe.
    float minRB = min(color.r, color.b);
    bool is_pink = (abs(color.r - color.b) <= 0.19) && 
                   (minRB > 0.01) && 
                   (color.g < minRB - 0.02);
    
    // 3. Blended boundary check:
    //    Any pixel where R and B are both high (minRB > 0.3) AND G is present (G > 0.05).
    //    Since heavy rain magenta/purple colors have G = 0.0, this is 100% safe.
    bool is_blend = (minRB > 0.3) && (color.g > 0.05);
    
    if (is_gray || is_pink || is_blend) {
        fragColor = vec4(0.0);
    } else {
        fragColor = color * qt_Opacity;
    }
}
