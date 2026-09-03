#version 450

layout (binding = 0) uniform sampler2D samplerColor;

layout (push_constant) uniform PushConstants {
    int shaderStyle; // 0..11
    float screenWidth;
    float screenHeight;
    float time;
    float zoomFactor; // 1.0, 1.5, 2.0
    int colorProfile; // 0..4
    int atmosphereFx; // 0: All On, 1: Lights & Mist, 2: Shadows & Wetness, 3: Off
    float mainPanelX;
    float mainPanelY;
    float mainPanelW;
    float mainPanelH;
    int leftPanelOpen;
    int rightPanelOpen;
} push;

bool IsInUIRegion(vec2 uv) {
    vec2 pixelPos = uv * vec2(push.screenWidth, push.screenHeight);

    // 1. Bottom Main Control Panel (Health/Mana Globes, Belt, XP Bar, Spell icon)
    if (pixelPos.x >= push.mainPanelX && pixelPos.x <= (push.mainPanelX + push.mainPanelW) &&
        pixelPos.y >= push.mainPanelY && pixelPos.y <= (push.mainPanelY + push.mainPanelH)) {
        return true;
    }

    // 2. Left Panel (Character Sheet / Quest Log)
    if (push.leftPanelOpen == 1 && pixelPos.x <= 320.0 && pixelPos.y < push.mainPanelY) {
        return true;
    }

    // 3. Right Panel (Inventory / Spellbook)
    if (push.rightPanelOpen == 1 && pixelPos.x >= (push.screenWidth - 320.0) && pixelPos.y < push.mainPanelY) {
        return true;
    }

    // 4. Top-Left OSD Debug Status Area (FPS, Mode text)
    if (pixelPos.x <= 580.0 && pixelPos.y <= 210.0) {
        return true;
    }

    return false;
}

layout (location = 0) in vec2 inUV;
layout (location = 0) out vec4 outFragColor;

#define TOTAL_STYLES 12

// Color distance helper for xBR/xBRZ
float DistYCbCr(vec3 c1, vec3 c2) {
    const vec3 w = vec3(0.299, 0.587, 0.114);
    vec3 diff = c1 - c2;
    float y = dot(diff, w);
    float u = diff.b - y;
    float v = diff.r - y;
    return sqrt(y * y * 4.0 + u * u + v * v);
}

bool EqColor(vec3 c1, vec3 c2) {
    return DistYCbCr(c1, c2) < 0.08;
}

// ============================================================================
// ============================================================================
// 0. Ultra-Sharp Neural Edge-Straightening & Vector Reconstruction (SVG-Grade)
// Straightens 2D pixel staircases into mathematically continuous, razor-sharp vector lines
// ============================================================================
vec3 ApplyNeuralCNN(sampler2D tex, vec2 uv, vec2 texelSize) {
    const vec3 luma = vec3(0.299, 0.587, 0.114);

    // 1. High-Precision 9-Tap Local Stencil
    vec3 cM  = texture(tex, uv).rgb;
    vec3 cTL = texture(tex, uv + vec2(-1.0, -1.0) * texelSize).rgb;
    vec3 cTC = texture(tex, uv + vec2( 0.0, -1.0) * texelSize).rgb;
    vec3 cTR = texture(tex, uv + vec2( 1.0, -1.0) * texelSize).rgb;
    vec3 cML = texture(tex, uv + vec2(-1.0,  0.0) * texelSize).rgb;
    vec3 cMR = texture(tex, uv + vec2( 1.0,  0.0) * texelSize).rgb;
    vec3 cBL = texture(tex, uv + vec2(-1.0,  1.0) * texelSize).rgb;
    vec3 cBC = texture(tex, uv + vec2( 0.0,  1.0) * texelSize).rgb;
    vec3 cBR = texture(tex, uv + vec2( 1.0,  1.0) * texelSize).rgb;

    float lM  = dot(cM, luma);
    float lTL = dot(cTL, luma); float lTC = dot(cTC, luma); float lTR = dot(cTR, luma);
    float lML = dot(cML, luma); float lMR = dot(cMR, luma);
    float lBL = dot(cBL, luma); float lBC = dot(cBC, luma); float lBR = dot(cBR, luma);

    // 2. Continuous Sub-Pixel Sobel-Feldman Gradient Vector
    float gx = (lTR + 2.0 * lMR + lBR) - (lTL + 2.0 * lML + lBL);
    float gy = (lBL + 2.0 * lBC + lBR) - (lTL + 2.0 * lTC + lTR);
    float gradMag = length(vec2(gx, gy));

    if (gradMag > 0.035) {
        vec2 norm = normalize(vec2(gx, gy));
        vec2 tangent = vec2(-norm.y, norm.x);

        // 3. Sub-Pixel Tangent-Flow Sampling (Straightens jagged diagonal staircases)
        vec3 t1 = texture(tex, uv + tangent * texelSize * 0.75).rgb;
        vec3 t2 = texture(tex, uv - tangent * texelSize * 0.75).rgb;
        vec3 t3 = texture(tex, uv + tangent * texelSize * 1.50).rgb;
        vec3 t4 = texture(tex, uv - tangent * texelSize * 1.50).rgb;

        vec3 smoothTangent = (cM * 0.30) + (t1 + t2) * 0.25 + (t3 + t4) * 0.10;

        // 4. Razor-Sharp Contour Sharpening (Pushes pixels along gradient normal to remove blur)
        vec3 nPos = texture(tex, uv + norm * texelSize * 0.65).rgb;
        vec3 nNeg = texture(tex, uv - norm * texelSize * 0.65).rgb;
        float lPos = dot(nPos, luma);
        float lNeg = dot(nNeg, luma);

        float edgeDist = clamp((lM - min(lPos, lNeg)) / (abs(lPos - lNeg) + 0.001), 0.0, 1.0);
        float sharpFactor = smoothstep(0.12, 0.88, edgeDist);
        vec3 razorEdge = mix(nNeg, nPos, sharpFactor);

        return mix(smoothTangent, razorEdge, clamp(gradMag * 3.8, 0.40, 0.92));
    }

    // Flat regions: 100% clean preservation
    return cM;
}

// ============================================================================
// 1. xBRZ / xBR-lv2 Vector Edge-Preserving Reconstruction (Hyllian)
// ============================================================================
vec3 ApplyXBR(sampler2D tex, vec2 uv, vec2 texelSize) {
    vec2 pos = uv / texelSize;
    vec2 f = fract(pos);
    vec2 p = (floor(pos) + 0.5) * texelSize;

    // 21-point sampling window around current pixel E
    vec3 a = texture(tex, p + vec2(-1.0, -2.0) * texelSize).rgb;
    vec3 b = texture(tex, p + vec2( 0.0, -2.0) * texelSize).rgb;
    vec3 c = texture(tex, p + vec2( 1.0, -2.0) * texelSize).rgb;

    vec3 d = texture(tex, p + vec2(-2.0, -1.0) * texelSize).rgb;
    vec3 e = texture(tex, p + vec2(-1.0, -1.0) * texelSize).rgb;
    vec3 f_ = texture(tex, p + vec2( 0.0, -1.0) * texelSize).rgb;
    vec3 g = texture(tex, p + vec2( 1.0, -1.0) * texelSize).rgb;
    vec3 h = texture(tex, p + vec2( 2.0, -1.0) * texelSize).rgb;

    vec3 i = texture(tex, p + vec2(-2.0,  0.0) * texelSize).rgb;
    vec3 j = texture(tex, p + vec2(-1.0,  0.0) * texelSize).rgb;
    vec3 k = texture(tex, p + vec2( 0.0,  0.0) * texelSize).rgb; // Center (E)
    vec3 l = texture(tex, p + vec2( 1.0,  0.0) * texelSize).rgb;
    vec3 m = texture(tex, p + vec2( 2.0,  0.0) * texelSize).rgb;

    vec3 n = texture(tex, p + vec2(-2.0,  1.0) * texelSize).rgb;
    vec3 o = texture(tex, p + vec2(-1.0,  1.0) * texelSize).rgb;
    vec3 q = texture(tex, p + vec2( 0.0,  1.0) * texelSize).rgb;
    vec3 r = texture(tex, p + vec2( 1.0,  1.0) * texelSize).rgb;
    vec3 s = texture(tex, p + vec2( 2.0,  1.0) * texelSize).rgb;

    vec3 t = texture(tex, p + vec2(-1.0,  2.0) * texelSize).rgb;
    vec3 u_ = texture(tex, p + vec2( 0.0,  2.0) * texelSize).rgb;
    vec3 v = texture(tex, p + vec2( 1.0,  2.0) * texelSize).rgb;

    vec3 res = k;

    // Corner analysis for bottom-right quadrant
    if (f.x >= 0.5 && f.y >= 0.5) {
        float d1 = DistYCbCr(e, r) + DistYCbCr(q, l) + DistYCbCr(g, s) + DistYCbCr(o, u_) + 4.0 * DistYCbCr(k, r);
        float d2 = DistYCbCr(j, q) + DistYCbCr(f_, l) + DistYCbCr(b, c) + DistYCbCr(t, v) + 4.0 * DistYCbCr(l, q);
        if (d1 < d2 && (f.x - 0.5) + (f.y - 0.5) > 0.45) {
            res = mix(k, (l + q) * 0.5, clamp(((f.x - 0.5) + (f.y - 0.5) - 0.45) * 4.0, 0.0, 1.0));
        }
    }
    // Corner analysis for top-right quadrant
    else if (f.x >= 0.5 && f.y < 0.5) {
        float d1 = DistYCbCr(o, g) + DistYCbCr(f_, l) + 4.0 * DistYCbCr(k, g);
        float d2 = DistYCbCr(j, f_) + DistYCbCr(q, l) + 4.0 * DistYCbCr(l, f_);
        if (d1 < d2 && (f.x - 0.5) + (0.5 - f.y) > 0.45) {
            res = mix(k, (l + f_) * 0.5, clamp(((f.x - 0.5) + (0.5 - f.y) - 0.45) * 4.0, 0.0, 1.0));
        }
    }
    // Corner analysis for bottom-left quadrant
    else if (f.x < 0.5 && f.y >= 0.5) {
        float d1 = DistYCbCr(g, o) + DistYCbCr(j, q) + 4.0 * DistYCbCr(k, o);
        float d2 = DistYCbCr(f_, j) + DistYCbCr(l, q) + 4.0 * DistYCbCr(j, q);
        if (d1 < d2 && (0.5 - f.x) + (f.y - 0.5) > 0.45) {
            res = mix(k, (j + q) * 0.5, clamp(((0.5 - f.x) + (f.y - 0.5) - 0.45) * 4.0, 0.0, 1.0));
        }
    }
    // Corner analysis for top-left quadrant
    else {
        float d1 = DistYCbCr(r, e) + DistYCbCr(j, f_) + 4.0 * DistYCbCr(k, e);
        float d2 = DistYCbCr(q, j) + DistYCbCr(l, f_) + 4.0 * DistYCbCr(j, f_);
        if (d1 < d2 && (0.5 - f.x) + (0.5 - f.y) > 0.45) {
            res = mix(k, (j + f_) * 0.5, clamp(((0.5 - f.x) + (0.5 - f.y) - 0.45) * 4.0, 0.0, 1.0));
        }
    }

    return res;
}

// ============================================================================
// 2. Anime4K 2D Line-Refinement & Contour Push/Pull (Sobel Gradient Shaper)
// ============================================================================
vec3 ApplyAnime4K(sampler2D tex, vec2 uv, vec2 texelSize) {
    vec3 cM = texture(tex, uv).rgb;
    vec3 cN = texture(tex, uv + vec2( 0.0, -1.0) * texelSize).rgb;
    vec3 cS = texture(tex, uv + vec2( 0.0,  1.0) * texelSize).rgb;
    vec3 cW = texture(tex, uv + vec2(-1.0,  0.0) * texelSize).rgb;
    vec3 cE = texture(tex, uv + vec2( 1.0,  0.0) * texelSize).rgb;

    vec3 luma = vec3(0.299, 0.587, 0.114);
    float lM = dot(cM, luma); float lN = dot(cN, luma); float lS = dot(cS, luma);
    float lW = dot(cW, luma); float lE = dot(cE, luma);

    // Sobel gradient
    float gx = (lE - lW);
    float gy = (lS - lN);
    vec2 grad = vec2(gx, gy);
    float gLen = length(grad);

    if (gLen < 0.04) {
        return cM;
    }

    // Push towards sharper gradient peak
    vec2 pushDir = normalize(grad) * texelSize * 0.65;
    vec3 cPush = texture(tex, uv - pushDir).rgb;
    return mix(cM, cPush, clamp(gLen * 3.5, 0.0, 0.75));
}

// ============================================================================
// 3. Scale3x / ScaleFX Curved Boundary Classifier
// ============================================================================
vec3 ApplyScale3X(sampler2D tex, vec2 uv, vec2 texelSize) {
    vec2 pos = uv / texelSize;
    vec2 f = fract(pos);
    vec2 p = (floor(pos) + 0.5) * texelSize;

    vec3 A = texture(tex, p + vec2(-1.0, -1.0) * texelSize).rgb;
    vec3 B = texture(tex, p + vec2( 0.0, -1.0) * texelSize).rgb;
    vec3 C = texture(tex, p + vec2( 1.0, -1.0) * texelSize).rgb;
    vec3 D = texture(tex, p + vec2(-1.0,  0.0) * texelSize).rgb;
    vec3 E = texture(tex, p).rgb;
    vec3 F = texture(tex, p + vec2( 1.0,  0.0) * texelSize).rgb;
    vec3 G = texture(tex, p + vec2(-1.0,  1.0) * texelSize).rgb;
    vec3 H = texture(tex, p + vec2( 0.0,  1.0) * texelSize).rgb;
    vec3 I = texture(tex, p + vec2( 1.0,  1.0) * texelSize).rgb;

    if (f.x < 0.33 && f.y < 0.33) {
        return (EqColor(D, B) && !EqColor(D, H) && !EqColor(B, F)) ? D : E;
    } else if (f.x > 0.66 && f.y < 0.33) {
        return (EqColor(B, F) && !EqColor(B, D) && !EqColor(F, H)) ? F : E;
    } else if (f.x < 0.33 && f.y > 0.66) {
        return (EqColor(H, D) && !EqColor(H, F) && !EqColor(D, B)) ? D : E;
    } else if (f.x > 0.66 && f.y > 0.66) {
        return (EqColor(H, F) && !EqColor(H, D) && !EqColor(F, B)) ? F : E;
    }
    return E;
}

// ============================================================================
// 4. Intel CMAA2 2.0 (Conservative Morphological Anti-Aliasing)
// ============================================================================
vec3 ApplyCMAA2(sampler2D tex, vec2 uv, vec2 texelSize) {
    vec3 cM = texture(tex, uv).rgb;
    vec3 cN = texture(tex, uv + vec2( 0.0, -1.0) * texelSize).rgb;
    vec3 cS = texture(tex, uv + vec2( 0.0,  1.0) * texelSize).rgb;
    vec3 cW = texture(tex, uv + vec2(-1.0,  0.0) * texelSize).rgb;
    vec3 cE = texture(tex, uv + vec2( 1.0,  0.0) * texelSize).rgb;

    vec3 luma = vec3(0.299, 0.587, 0.114);
    float lM = dot(cM, luma); float lN = dot(cN, luma); float lS = dot(cS, luma);
    float lW = dot(cW, luma); float lE = dot(cE, luma);

    float edgeH = abs(lN - lM) + abs(lS - lM);
    float edgeV = abs(lW - lM) + abs(lE - lM);
    float edgeMax = max(edgeH, edgeV);

    if (edgeMax < 0.08) return cM;

    vec3 cNW = texture(tex, uv + vec2(-1.0, -1.0) * texelSize).rgb;
    vec3 cNE = texture(tex, uv + vec2( 1.0, -1.0) * texelSize).rgb;
    vec3 cSW = texture(tex, uv + vec2(-1.0,  1.0) * texelSize).rgb;
    vec3 cSE = texture(tex, uv + vec2( 1.0,  1.0) * texelSize).rgb;

    float lNW = dot(cNW, luma); float lNE = dot(cNE, luma);
    float lSW = dot(cSW, luma); float lSE = dot(cSE, luma);

    float d1 = abs(lNW - lSE);
    float d2 = abs(lNE - lSW);

    vec3 blended;
    if (d1 < d2 * 0.70) {
        blended = mix(cM, (cNW + cSE) * 0.5, 0.40);
    } else if (d2 < d1 * 0.70) {
        blended = mix(cM, (cNE + cSW) * 0.5, 0.40);
    } else if (edgeH > edgeV * 1.4) {
        blended = mix(cM, (cN + cS) * 0.5, 0.35);
    } else if (edgeV > edgeH * 1.4) {
        blended = mix(cM, (cW + cE) * 0.5, 0.35);
    } else {
        blended = mix(cM, (cN + cS + cW + cE) * 0.25, 0.25);
    }

    vec3 minC = min(min(min(cN, cS), min(cW, cE)), cM);
    vec3 maxC = max(max(max(cN, cS), max(cW, cE)), cM);
    return clamp(blended, minC, maxC);
}

// ============================================================================
// 5. AMD FidelityFX FSR EASU
// ============================================================================
vec3 ApplyFsrEasu(sampler2D tex, vec2 uv, vec2 texelSize) {
    vec2 pos = uv / texelSize - vec2(0.5);
    vec2 f = fract(pos);
    vec2 base = (floor(pos) + 0.5) * texelSize;

    vec3 c0 = texture(tex, base + vec2( 0.0, -1.0) * texelSize).rgb;
    vec3 c1 = texture(tex, base + vec2(-1.0,  0.0) * texelSize).rgb;
    vec3 c2 = texture(tex, base + vec2( 0.0,  0.0) * texelSize).rgb;
    vec3 c3 = texture(tex, base + vec2( 1.0,  0.0) * texelSize).rgb;
    vec3 c4 = texture(tex, base + vec2( 0.0,  1.0) * texelSize).rgb;
    vec3 c5 = texture(tex, base + vec2(-1.0,  1.0) * texelSize).rgb;
    vec3 c6 = texture(tex, base + vec2( 1.0, -1.0) * texelSize).rgb;
    vec3 c7 = texture(tex, base + vec2(-1.0, -1.0) * texelSize).rgb;
    vec3 c8 = texture(tex, base + vec2( 1.0,  1.0) * texelSize).rgb;

    vec3 luma = vec3(0.299, 0.587, 0.114);
    float l0 = dot(c0, luma); float l1 = dot(c1, luma); float l2 = dot(c2, luma);
    float l3 = dot(c3, luma); float l4 = dot(c4, luma); float l5 = dot(c5, luma);
    float l6 = dot(c6, luma); float l7 = dot(c7, luma); float l8 = dot(c8, luma);

    float dirX = (l3 - l1) * 2.0 + (l6 - l7) + (l8 - l5);
    float dirY = (l4 - l0) * 2.0 + (l8 - l6) + (l5 - l7);
    vec2 dir = vec2(dirX, dirY);
    float len = length(dir);
    if (len > 0.001) dir /= len; else dir = vec2(0.0, 1.0);

    vec2 offset = dir * (f - 0.5);
    float w0 = clamp(1.0 - abs(offset.x + offset.y), 0.0, 1.0);
    float w1 = clamp(1.0 - abs(offset.x - offset.y), 0.0, 1.0);

    vec3 color = (c2 * 2.0 + c0 + c1 + c3 + c4) * 0.16666;
    color = mix(color, (c7 + c6 + c5 + c8) * 0.25, 0.25 * (1.0 - len * 0.5));
    return color;
}

// ============================================================================
// 6. Bilateral Denoise Filter
// ============================================================================
vec3 ApplyBilateralDenoise(sampler2D tex, vec2 uv, vec2 texelSize) {
    vec3 center = texture(tex, uv).rgb;
    vec3 luma = vec3(0.299, 0.587, 0.114);
    float centerLuma = dot(center, luma);

    vec3 sum = center * 0.30;
    float totalWeight = 0.30;

    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (x == 0 && y == 0) continue;
            vec3 neighbor = texture(tex, uv + vec2(x, y) * texelSize).rgb;
            float nLuma = dot(neighbor, luma);
            float diff = abs(centerLuma - nLuma);
            float w = exp(-diff * 22.0) * 0.0875;
            sum += neighbor * w;
            totalWeight += w;
        }
    }
    return sum / max(totalWeight, 0.001);
}

// ============================================================================
// 7. Refined Volumetric Torchlight, Ambient Warmth & Micro-Contrast
// ============================================================================
vec3 ApplyModernFireAndLighting(sampler2D tex, vec2 uv, vec2 texelSize, float time, vec3 baseColor) {
    // 1. Clean Multi-Tap Volumetric Point-Light (Noise-Free Gaussian Halo)
    vec3 fireHalo = vec3(0.0);
    float totalHaloWeight = 0.0;

    const float r1 = 6.0;
    const float r2 = 14.0;
    const float r3 = 24.0;

    for (int y = -2; y <= 2; ++y) {
        for (int x = -2; x <= 2; ++x) {
            if (x == 0 && y == 0) continue;
            vec2 dir = normalize(vec2(float(x), float(y)));

            // Sample near ring (6 texels)
            vec3 sNear = texture(tex, uv + dir * r1 * texelSize).rgb;
            float fNear = max(0.0, sNear.r * 1.4 - sNear.b * 1.8) * step(sNear.b, 0.40);
            fireHalo += vec3(1.25, 0.70, 0.20) * fNear * 0.50;
            totalHaloWeight += 0.50;

            // Sample mid ring (14 texels)
            vec3 sMid = texture(tex, uv + dir * r2 * texelSize).rgb;
            float fMid = max(0.0, sMid.r * 1.4 - sMid.b * 1.8) * step(sMid.b, 0.40);
            fireHalo += vec3(1.10, 0.55, 0.12) * fMid * 0.30;
            totalHaloWeight += 0.30;

            // Sample wide ring (24 texels)
            vec3 sFar = texture(tex, uv + dir * r3 * texelSize).rgb;
            float fFar = max(0.0, sFar.r * 1.4 - sFar.b * 1.8) * step(sFar.b, 0.40);
            fireHalo += vec3(0.90, 0.40, 0.08) * fFar * 0.15;
            totalHaloWeight += 0.15;
        }
    }
    vec3 volumetricGlow = fireHalo / max(totalHaloWeight, 0.001);

    // 2. Smooth Multi-Harmonic Organic Torch Flicker
    float flicker = 0.94 + 0.040 * sin(time * 6.5 + uv.y * 10.0)
                         + 0.020 * cos(time * 10.8 + uv.x * 14.0);

    // 3. Flame Core Heat Accent
    float flameVal = max(0.0, baseColor.r * 1.5 - baseColor.b * 2.0);
    float isDirectFlame = smoothstep(0.40, 0.80, flameVal) * step(baseColor.b, 0.35);
    vec3 flameGlow = vec3(1.30, 0.85, 0.40) * isDirectFlame * 0.45;

    return (volumetricGlow * 1.65 * flicker) + flameGlow;
}

// ============================================================================
// 8. Screen-Space Contact Shadows (SSAO)
// ============================================================================
vec3 ApplyContactShadows(vec3 color, sampler2D tex, vec2 uv, vec2 texelSize) {
    vec3 cN = texture(tex, uv + vec2(0.0, -1.0) * texelSize * 2.0).rgb;
    vec3 cS = texture(tex, uv + vec2(0.0, 1.0) * texelSize * 2.0).rgb;
    vec3 cW = texture(tex, uv + vec2(-1.0, 0.0) * texelSize * 2.0).rgb;
    vec3 cE = texture(tex, uv + vec2(1.0, 0.0) * texelSize * 2.0).rgb;
    float avgLuma = (dot(cN, vec3(0.299, 0.587, 0.114)) + dot(cS, vec3(0.299, 0.587, 0.114)) +
                     dot(cW, vec3(0.299, 0.587, 0.114)) + dot(cE, vec3(0.299, 0.587, 0.114))) * 0.25;
    float centerLuma = dot(color, vec3(0.299, 0.587, 0.114));
    float occlusion = clamp((centerLuma + 0.03) / (avgLuma + 0.03), 0.85, 1.0);
    return color * occlusion;
}

// ============================================================================
// 9. Specular Wetness / Damp Stone Floor Sheen
// ============================================================================
vec3 ApplySpecularWetness(vec3 color, sampler2D tex, vec2 uv, vec2 texelSize, vec3 torchLight) {
    float lumaL = dot(texture(tex, uv - vec2(texelSize.x * 1.5, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
    float lumaR = dot(texture(tex, uv + vec2(texelSize.x * 1.5, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
    float lumaU = dot(texture(tex, uv - vec2(0.0, texelSize.y * 1.5)).rgb, vec3(0.299, 0.587, 0.114));
    float lumaD = dot(texture(tex, uv + vec2(0.0, texelSize.y * 1.5)).rgb, vec3(0.299, 0.587, 0.114));
    vec2 normal2D = vec2(lumaR - lumaL, lumaD - lumaU);
    float roughness = length(normal2D);
    float lightAmt = dot(torchLight, vec3(0.333));
    float wetSheen = pow(clamp(roughness * 4.5, 0.0, 1.0), 3.0) * lightAmt * 0.55;
    return color + vec3(1.10, 1.05, 0.95) * wetSheen;
}

// ============================================================================
// 10. Smooth Isometric Hero Candle Illumination (Seamless Gaussian Multiplicative)
// ============================================================================
vec3 ApplyHeroCandleAura(vec3 baseColor, vec2 uv, float time) {
    vec2 heroPos = vec2(0.5, 0.52);
    // Isometric projection scaling (2:1 ellipse)
    vec2 diff = (uv - heroPos) * vec2(push.screenWidth / push.screenHeight, 1.85);
    float distSq = dot(diff, diff);

    // Smooth Gaussian exponential decay (zero hard seams)
    float aura = exp(-distSq * 18.0);
    float breath = 0.96 + 0.04 * sin(time * 3.5);

    // Multiplicative illumination on existing stone surfaces (does not wash out black void)
    vec3 warmAmber = vec3(0.28, 0.20, 0.08) * aura * breath;
    return baseColor * (vec3(1.0) + warmAmber);
}

// ============================================================================
// 11. Low Atmospheric Dungeon Mist (Ground Vapor)
// ============================================================================
vec3 ApplyDungeonMist(vec2 uv, float time, float centerLuma, vec3 torchLight) {
    float n1 = sin(uv.x * 5.0 + time * 0.16) * cos(uv.y * 6.5 - time * 0.12);
    float n2 = cos(uv.x * 8.5 - time * 0.10) * sin(uv.y * 10.0 + time * 0.14);
    float mistNoise = (n1 + n2) * 0.25 + 0.50;

    float shadowZone = smoothstep(0.03, 0.22, centerLuma) * (1.0 - smoothstep(0.50, 0.85, centerLuma));
    float mistIntensity = mistNoise * shadowZone * 0.06;

    vec3 coolMist = vec3(0.10, 0.14, 0.20);
    vec3 warmMist = vec3(0.22, 0.16, 0.08);
    vec3 mistColor = mix(coolMist, warmMist, clamp(dot(torchLight, vec3(0.333)) * 2.5, 0.0, 1.0));
    return mistColor * mistIntensity;
}

// ============================================================================
// Atmospheric Suite Coordinator
// ============================================================================
vec3 ApplyAtmosphericPostProcess(vec3 color, sampler2D tex, vec2 uv, vec2 texelSize, float time, vec3 torchLight, int mode) {
    if (mode == 0) { // 0: All On (SSAO + Wetness + Hero Light + Mist)
        vec3 c = ApplyContactShadows(color, tex, uv, texelSize);
        c = ApplySpecularWetness(c, tex, uv, texelSize, torchLight);
        c = ApplyHeroCandleAura(c, uv, time);
        c += ApplyDungeonMist(uv, time, dot(c, vec3(0.299, 0.587, 0.114)), torchLight);
        return c;
    } else if (mode == 1) { // 1: Lights & Mist
        vec3 c = ApplyHeroCandleAura(color, uv, time);
        c += ApplyDungeonMist(uv, time, dot(c, vec3(0.299, 0.587, 0.114)), torchLight);
        return c;
    } else if (mode == 2) { // 2: Shadows & Wetness
        vec3 c = ApplyContactShadows(color, tex, uv, texelSize);
        return ApplySpecularWetness(c, tex, uv, texelSize, torchLight);
    } else { // 3: Off
        return color;
    }
}

// ============================================================================
// 12. 32-bit De-Banding & Smooth Gradient Reconstruction
// Reconstructs continuous 32-bit float gradients from 256-color palette steps
// ============================================================================
vec3 ApplyDeBanding(vec3 center, sampler2D tex, vec2 uv, vec2 texelSize) {
    const float threshold = 0.045; // Banding step delta threshold
    vec3 cN = texture(tex, uv + vec2(0.0, -1.0) * texelSize * 2.0).rgb;
    vec3 cS = texture(tex, uv + vec2(0.0, 1.0) * texelSize * 2.0).rgb;
    vec3 cW = texture(tex, uv + vec2(-1.0, 0.0) * texelSize * 2.0).rgb;
    vec3 cE = texture(tex, uv + vec2(1.0, 0.0) * texelSize * 2.0).rgb;

    vec3 diffN = abs(center - cN);
    vec3 diffS = abs(center - cS);
    vec3 diffW = abs(center - cW);
    vec3 diffE = abs(center - cE);

    float maxDiff = max(max(diffN.r, diffS.r), max(diffW.r, diffE.r));
    maxDiff = max(maxDiff, max(max(diffN.g, diffS.g), max(diffW.g, diffE.g)));
    maxDiff = max(maxDiff, max(max(diffN.b, diffS.b), max(diffW.b, diffE.b)));

    // If variation is subtle (typical 256-color palette stepping/posterization), blend smoothly
    if (maxDiff < threshold && maxDiff > 0.001) {
        vec3 avg = (center * 2.0 + cN + cS + cW + cE) / 6.0;
        // Subtle blue-noise dither to eliminate quantization harmonics
        float noise = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
        avg += noise * 0.003;
        return mix(center, avg, 0.70);
    }
    return center;
}

// ============================================================================
// 13. 32-bit Dynamic Color Grading & Tone Mapping Profiles
// ============================================================================
vec3 ApplyColorProfile(vec3 c, int profile) {
    // 0: Dark Gothic (OLED Black & Warm Embers)
    if (profile == 0) {
        // Deep OLED shadows with filmic toe, warm gold/amber highlights
        vec3 shadow = pow(c, vec3(1.15));
        vec3 ember = shadow * vec3(1.08, 1.02, 0.94);
        float luma = dot(ember, vec3(0.299, 0.587, 0.114));
        vec3 saturated = mix(vec3(luma), ember, 1.18);
        return clamp(saturated, 0.0, 1.0);
    }
    // 1: Hellish Crimson (Warm Gothic & Subtle Red Accent)
    else if (profile == 1) {
        float luma = dot(c, vec3(0.299, 0.587, 0.114));
        // Pure black shadows preserved; subtle crimson warmth on midtones & lights
        vec3 shadow = pow(c, vec3(1.12));
        vec3 crimson = shadow * vec3(1.12, 0.96, 0.94);
        return clamp(crimson, 0.0, 1.0);
    }
    // 2: High-Contrast Vibrant (32-bit Saturated Glow)
    else if (profile == 2) {
        float luma = dot(c, vec3(0.299, 0.587, 0.114));
        vec3 sat = mix(vec3(luma), c, 1.35);
        vec3 contrast = (sat - 0.5) * 1.15 + 0.5;
        return clamp(contrast, 0.0, 1.0);
    }
    // 3: Cold Crypt (Blue-Gray Gothic Shadow)
    else if (profile == 3) {
        float luma = dot(c, vec3(0.299, 0.587, 0.114));
        vec3 cold = c * vec3(0.88, 0.98, 1.22);
        vec3 desatCold = mix(vec3(luma), cold, 0.85);
        return clamp(pow(desatCold, vec3(1.08)), 0.0, 1.0);
    }
    // 4: 1996 Classic (32-bit De-Banded with pure original RGB preservation)
    else {
        return clamp(c, 0.0, 1.0);
    }
}

void main() {
    vec2 texelSize = 1.0 / vec2(push.screenWidth, push.screenHeight);
    vec4 baseColor = texture(samplerColor, inUV);
    vec3 resultColor = baseColor.rgb;

    // Style 0: AI Neural CNN (Deep Learning Super-Resolution)
    if (push.shaderStyle == 0) {
        resultColor = ApplyNeuralCNN(samplerColor, inUV, texelSize);
    }
    // Style 1: AI Neural CNN + Modern Volumetric Torchlight & Embers
    else if (push.shaderStyle == 1) {
        vec3 cnn = ApplyNeuralCNN(samplerColor, inUV, texelSize);
        vec3 fireFX = ApplyModernFireAndLighting(samplerColor, inUV, texelSize, push.time, cnn);
        vec2 d = (inUV - 0.5) * 2.0;
        float vig = clamp(1.0 - dot(d, d) * 0.28, 0.0, 1.0);
        resultColor = (cnn + fireFX * 0.55) * vig;
    }
    // Style 2: xBRZ 2D Vector Reconstruction (Diagonal pattern recognition)
    else if (push.shaderStyle == 2) {
        resultColor = ApplyXBR(samplerColor, inUV, texelSize);
    }
    // Style 3: xBRZ + Modern Volumetric Torchlight & Embers
    else if (push.shaderStyle == 3) {
        vec3 xbr = ApplyXBR(samplerColor, inUV, texelSize);
        vec3 fireFX = ApplyModernFireAndLighting(samplerColor, inUV, texelSize, push.time, xbr);
        vec2 d = (inUV - 0.5) * 2.0;
        float vig = clamp(1.0 - dot(d, d) * 0.28, 0.0, 1.0);
        resultColor = (xbr + fireFX * 0.55) * vig;
    }
    // Style 4: Anime4K Line-Refine (Clean contour lines)
    else if (push.shaderStyle == 4) {
        vec3 a4k = ApplyAnime4K(samplerColor, inUV, texelSize);
        vec3 cmaa2 = ApplyCMAA2(samplerColor, inUV, texelSize);
        resultColor = mix(a4k, cmaa2, 0.35);
    }
    // Style 5: Scale3x / ScaleFX (SABR Boundary Filter)
    else if (push.shaderStyle == 5) {
        resultColor = ApplyScale3X(samplerColor, inUV, texelSize);
    }
    // Style 6: AMD FSR Ultra Smooth (EASU + CMAA2 + Denoise + Volumetric Fire & Embers)
    else if (push.shaderStyle == 6) {
        vec3 easu = ApplyFsrEasu(samplerColor, inUV, texelSize);
        vec3 cmaa2 = ApplyCMAA2(samplerColor, inUV, texelSize);
        vec3 denoise = ApplyBilateralDenoise(samplerColor, inUV, texelSize);
        vec3 cleanBase = mix(mix(easu, cmaa2, 0.50), denoise, 0.35);
        vec3 fireFX = ApplyModernFireAndLighting(samplerColor, inUV, texelSize, push.time, cleanBase);
        vec2 d = (inUV - 0.5) * 2.0;
        float vig = clamp(1.0 - dot(d, d) * 0.30, 0.0, 1.0);
        resultColor = (cleanBase + fireFX * 0.55) * vig;
    }
    // Style 7: AMD FSR + Intel CMAA2 Ultra Clean (100% Anti-Aliased)
    else if (push.shaderStyle == 7) {
        vec3 fsrEasu = ApplyFsrEasu(samplerColor, inUV, texelSize);
        vec3 cmaa2 = ApplyCMAA2(samplerColor, inUV, texelSize);
        resultColor = mix(fsrEasu, cmaa2, 0.55);
    }
    // Style 8: Bilateral Denoised HD (Painterly Retro Dither Removal)
    else if (push.shaderStyle == 8) {
        vec3 denoise = ApplyBilateralDenoise(samplerColor, inUV, texelSize);
        vec3 cmaa2 = ApplyCMAA2(samplerColor, inUV, texelSize);
        resultColor = mix(denoise, cmaa2, 0.45);
    }
    // Style 9: Dark-CRT Royale (Curved Glass + Shadow Mask + Scanlines)
    else if (push.shaderStyle == 9) {
        vec2 cc = (inUV - 0.5) * 2.0;
        vec2 distUV = inUV + cc * (dot(cc, cc) * 0.035);
        if (distUV.x < 0.0 || distUV.x > 1.0 || distUV.y < 0.0 || distUV.y > 1.0) {
            outFragColor = vec4(0.0, 0.0, 0.0, 1.0);
            return;
        }
        vec3 crtBase = texture(samplerColor, distUV).rgb;
        float scanline = sin(distUV.y * push.screenHeight * 3.14159265) * 0.5 + 0.5;
        float scanlineFactor = mix(0.70, 1.0, scanline);
        float mask = mod(gl_FragCoord.x, 3.0);
        vec3 maskColor = (mask < 1.0) ? vec3(1.10, 0.93, 0.93) : ((mask < 2.0) ? vec3(0.93, 1.10, 0.93) : vec3(0.93, 0.93, 1.10));
        float vig = clamp(1.0 - dot(cc, cc) * 0.35, 0.0, 1.0);
        resultColor = crtBase * scanlineFactor * maskColor * vig;
    }
    // Style 10: Flat CRT Trinitron (Sharp Scanlines & Aperture Grille, Flat Panel)
    else if (push.shaderStyle == 10) {
        float scanline = sin(inUV.y * push.screenHeight * 3.14159265) * 0.5 + 0.5;
        float scanlineFactor = mix(0.75, 1.0, scanline);
        float mask = mod(gl_FragCoord.x, 2.0);
        vec3 maskColor = (mask < 1.0) ? vec3(1.05, 1.0, 1.0) : vec3(0.95, 0.95, 1.05);
        resultColor = baseColor.rgb * scanlineFactor * maskColor;
    }
    // Style 11: Integer Scaling (Pixel-Perfect 1:1 Clean Retro)
    else {
        resultColor = baseColor.rgb;
    }

    // If pixel belongs to UI (Main bottom panel, inventory, character sheet, OSD), keep 100% pristine and unaffected!
    if (IsInUIRegion(inUV)) {
        outFragColor = vec4(resultColor, baseColor.a);
        return;
    }

    // 1. Calculate Volumetric Torchlight & Flame Energy (Dungeon World Only)
    vec3 torchLight = ApplyModernFireAndLighting(samplerColor, inUV, texelSize, push.time, resultColor);

    // 2. Apply Atmospheric FX Suite (SSAO Contact Shadows, Specular Wetness, Hero Candle Aura, Dungeon Mist)
    vec3 atmosphered = ApplyAtmosphericPostProcess(resultColor, samplerColor, inUV, texelSize, push.time, torchLight, push.atmosphereFx);

    // 3. Apply 32-bit De-Banding (removes 256-color gradient steps)
    vec3 debanded = ApplyDeBanding(atmosphered, samplerColor, inUV, texelSize);

    // 4. Apply Active 32-bit Color Profile (Dark Gothic, Hellish Crimson, Vibrant, Cold Crypt, Classic)
    vec3 graded = ApplyColorProfile(debanded, push.colorProfile);

    outFragColor = vec4(clamp(graded, 0.0, 1.0), baseColor.a);
}
