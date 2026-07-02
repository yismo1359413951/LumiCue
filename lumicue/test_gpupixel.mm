// 独立测试: 验证 GpuPixel 引擎 + 离屏 OpenGL 在本机能否跑出非黑美颜。
// 用法: ./gp-test <resourceDir> <inputImage>
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#include <cstdio>
#include <vector>
#include "gpupixel/gpupixel.h"
using namespace gpupixel;

int main(int argc, char** argv) {
  @autoreleasepool {
    if (argc < 3) { printf("usage: gp-test <resDir> <img>\n"); return 2; }

    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        NSOpenGLPFAAccelerated, NSOpenGLPFAColorSize, 32, 0};
    NSOpenGLPixelFormat* pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    NSOpenGLContext* ctx = [[NSOpenGLContext alloc] initWithFormat:pf shareContext:nil];
    if (!ctx) { printf("FAIL: no NSOpenGLContext\n"); return 1; }
    [ctx makeCurrentContext];

    GPUPixel::SetResourcePath(argv[1]);
    auto source = SourceRawData::Create();
    auto beauty = BeautyFaceFilter::Create();
    auto sink = SinkRawData::Create();
    if (!source || !beauty || !sink) { printf("FAIL: filter create\n"); return 1; }
    source->AddSink(beauty)->AddSink(sink);
    beauty->SetBlurAlpha(0.8f);
    beauty->SetWhite(0.3f);

    NSImage* img = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
    if (!img) { printf("FAIL: load image\n"); return 1; }
    CGImageRef cg = [img CGImageForProposedRect:nil context:nil hints:nil];
    int w = (int)CGImageGetWidth(cg), h = (int)CGImageGetHeight(cg);
    std::vector<uint8_t> in(w * h * 4, 0);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bm = CGBitmapContextCreate(in.data(), w, h, 8, w * 4, cs,
                                            kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(bm, CGRectMake(0, 0, w, h), cg);
    long isum = 0; for (size_t i = 0; i < in.size(); i++) isum += in[i];
    printf("input  %dx%d mean=%.1f\n", w, h, (double)isum / in.size());

    source->ProcessData(in.data(), w, h, w * 4, GPUPIXEL_FRAME_TYPE_RGBA);
    const uint8_t* out = sink->GetRgbaBuffer();
    int ow = sink->GetWidth(), oh = sink->GetHeight();
    printf("output rgba=%p %dx%d\n", (const void*)out, ow, oh);
    if (!out || ow <= 0 || oh <= 0) { printf("FAIL: null/empty output\n"); return 1; }

    long osum = 0; for (int i = 0; i < ow * oh * 4; i++) osum += out[i];
    double omean = (double)osum / (ow * oh * 4);
    printf("output mean=%.1f  (0=全黑, 接近input=正常)\n", omean);

    CGContextRef obm = CGBitmapContextCreate((void*)out, ow, oh, 8, ow * 4, cs,
                                             kCGImageAlphaPremultipliedLast);
    CGImageRef ocg = CGBitmapContextCreateImage(obm);
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithCGImage:ocg];
    NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:@"/tmp/gp-test-out.png" atomically:YES];
    printf("saved /tmp/gp-test-out.png  →  %s\n", omean < 1.0 ? "❌全黑" : "✅有内容");
  }
  return 0;
}
