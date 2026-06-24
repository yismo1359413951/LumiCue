//
//  Beauty.metal
//  Snapzy (靓相 Shotlit)
//
//  Real-time beauty compute shader 实时美颜着色器
//  — face-slimming(瘦脸液化) + bilateral smoothing(双边磨皮) + whitening(美白).
//

#include <metal_stdlib>
using namespace metal;

// face: (centerX, centerY, width, thinStrength)  归一化坐标(Metal 左上原点)
kernel void beautyKernel(
    texture2d<float, access::read>  inTex   [[texture(0)]],
    texture2d<float, access::write> outTex  [[texture(1)]],
    constant float &smoothing               [[buffer(0)]],
    constant float &whitening               [[buffer(1)]],
    constant float4 &face                   [[buffer(2)]],
    constant float &chin                    [[buffer(3)]],
    constant float2 &chinPos                 [[buffer(4)]],
    uint2 gid                               [[thread_position_in_grid]])
{
    const uint W = inTex.get_width();
    const uint H = inTex.get_height();
    if (gid.x >= W || gid.y >= H) { return; }

    float2 uv = float2(float(gid.x) / float(W), float(gid.y) / float(H));
    float2 readUV = uv;

    // 瘦脸: 脸颊区域向中线水平挤压(采样位置向外偏移 => 脸收窄)
    float thin = face.w;
    if (thin > 0.01 && face.z > 0.01) {
        float2 fc = float2(face.x, face.y);
        float fw = face.z;
        float dx = uv.x - fc.x;
        float dy = uv.y - fc.y;
        // 只在人脸椭圆区域内液化, 背景完全不动(修复背景变形)
        float faceDist = length(float2(dx / (fw * 0.6), dy / (fw * 0.85)));
        float faceMask = smoothstep(1.05, 0.55, faceDist);
        float vfall = smoothstep(fw * 0.9, 0.0, abs(dy)); // 垂直衰减(脸中下部最强)
        float hnorm = clamp(abs(dx) / (fw * 0.55), 0.0, 1.0);
        float ramp = smoothstep(0.15, 0.95, hnorm); // 脸边缘强、中心不动
        float amount = thin * vfall * ramp * faceMask * 0.13;
        readUV.x += sign(dx) * amount * fw;
    }

    // 下巴瘦脸: 用精确下巴尖关键点, 下巴区域向上收缩(下巴变短变尖)
    if (chin > 0.01 && face.z > 0.01) {
        float fw = face.z;
        float dx = uv.x - chinPos.x;          // 精确下巴尖 x
        float dyc = uv.y - chinPos.y;         // 精确下巴尖 y
        float chinMask = smoothstep(0.5, 0.0, length(float2(dx / (fw * 0.45), dyc / (fw * 0.4))));
        readUV.x += sign(dx) * chin * chinMask * fw * 0.15; // 左右向中收窄(下巴变尖, 不是上下)
        readUV.y += chin * chinMask * fw * 0.03;            // 轻微上提
    }

    uint2 base = uint2(clamp(readUV.x * float(W), 0.0, float(W - 1)),
                       clamp(readUV.y * float(H), 0.0, float(H - 1)));
    float3 center = inTex.read(base).rgb;

    // 磨皮: 双边滤波(围绕瘦脸后采样点, 平滑皮肤保留五官)
    if (smoothing > 0.01) {
        const int radius = 4;
        const float sigmaSpace = 5.0;
        const float sigmaColor = 0.06 + 0.22 * smoothing;
        float3 sum = float3(0.0);
        float wsum = 0.0;
        for (int dy = -radius; dy <= radius; dy++) {
            for (int dx = -radius; dx <= radius; dx++) {
                int sx = clamp(int(base.x) + dx, 0, int(W) - 1);
                int sy = clamp(int(base.y) + dy, 0, int(H) - 1);
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
        float3 detail = center - smooth;
        float3 result = smooth + detail * (1.0 - smoothing) * 0.6;
        center = mix(center, result, clamp(smoothing * 1.2, 0.0, 1.0));
    }

    // 美白
    if (whitening > 0.01) {
        center += whitening * 0.14;
        float gray = dot(center, float3(0.299, 0.587, 0.114));
        center = mix(center, float3(gray), whitening * 0.06);
    }

    // 面部补光(打光感): 脸中心径向柔光提亮, 中心亮、边缘自然渐隐 => 立体不死平
    // 用高光 lift(往白推)而非整体加值, 保留五官立体感, 不发灰
    if (face.z > 0.01) {
        float2 fc = float2(face.x, face.y);
        float fd = length((uv - fc) / (face.z * 1.5));
        float lite = exp(-fd * fd * 0.5) * 0.55;       // 高斯柔光: 中心最强
        center += lite * (1.0 - center) * 0.55;        // 高光 lift, 保立体
    }

    center = clamp(center, 0.0, 1.0);
    outTex.write(float4(center, 1.0), gid);
}
