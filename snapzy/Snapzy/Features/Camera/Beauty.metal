//
//  Beauty.metal
//  Snapzy (靓相 Shotlit)
//
//  Real-time beauty compute shader 实时美颜着色器
//  — bilateral filter smoothing(双边滤波磨皮, 保边不糊) + whitening(美白).
//

#include <metal_stdlib>
using namespace metal;

// 双边滤波磨皮 + 美白
// smoothing/whitening: 0~1 强度
kernel void beautyKernel(
    texture2d<float, access::read>  inTex   [[texture(0)]],
    texture2d<float, access::write> outTex  [[texture(1)]],
    constant float &smoothing               [[buffer(0)]],
    constant float &whitening               [[buffer(1)]],
    uint2 gid                               [[thread_position_in_grid]])
{
    const uint W = inTex.get_width();
    const uint H = inTex.get_height();
    if (gid.x >= W || gid.y >= H) { return; }

    float3 center = inTex.read(gid).rgb;

    if (smoothing > 0.01) {
        // 双边滤波: 空间高斯 × 颜色相似度 → 平滑皮肤、保留边缘
        const int radius = 4;
        const float sigmaSpace = 5.0;
        const float sigmaColor = 0.06 + 0.22 * smoothing; // 越大磨皮越狠
        float3 sum = float3(0.0);
        float wsum = 0.0;
        for (int dy = -radius; dy <= radius; dy++) {
            for (int dx = -radius; dx <= radius; dx++) {
                int sx = clamp(int(gid.x) + dx, 0, int(W) - 1);
                int sy = clamp(int(gid.y) + dy, 0, int(H) - 1);
                float3 s = inTex.read(uint2(sx, sy)).rgb;
                float ws = exp(-float(dx * dx + dy * dy) / (2.0 * sigmaSpace * sigmaSpace));
                float3 d = s - center;
                float wc = exp(-dot(d, d) / (2.0 * sigmaColor * sigmaColor));
                float w = ws * wc;
                sum += s * w;
                wsum += w;
            }
        }
        float3 smooth = (wsum > 0.0) ? (sum / wsum) : center;
        // 高反差保留: 把磨掉的高频细节(五官锐度)按比例加回, 防止糊
        float3 detail = center - smooth;
        float3 result = smooth + detail * (1.0 - smoothing) * 0.6;
        center = mix(center, result, clamp(smoothing * 1.2, 0.0, 1.0));
    }

    // 美白: 提亮 + 轻微降饱和
    if (whitening > 0.01) {
        center += whitening * 0.14;
        float gray = dot(center, float3(0.299, 0.587, 0.114));
        center = mix(center, float3(gray), whitening * 0.06);
    }

    center = clamp(center, 0.0, 1.0);
    outTex.write(float4(center, 1.0), gid);
}
