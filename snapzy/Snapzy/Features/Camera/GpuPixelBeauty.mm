//
//  GpuPixelBeauty.mm
//  Snapzy (靓相 Shotlit)
//
//  ObjC++ implementation bridging Swift ↔ GpuPixel C++ engine.
//

#import "GpuPixelBeauty.h"
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>

#include <memory>
#include <string>
#include <vector>

#include "gpupixel/gpupixel.h"

using namespace gpupixel;

@implementation GpuPixelBeauty {
  NSOpenGLContext *_glContext;
  std::shared_ptr<SourceRawData> _source;
  std::shared_ptr<SinkRawData> _sink;
  std::shared_ptr<BeautyFaceFilter> _beauty;
  std::shared_ptr<FaceReshapeFilter> _reshape;
  std::shared_ptr<FaceDetector> _detector;
}

- (nullable instancetype)initWithResourcePath:(NSString *)resourcePath {
  if (!(self = [super init])) return nil;

  // 1. 建一个离屏 OpenGL 上下文(GpuPixel 用 OpenGL 渲染)
  NSOpenGLPixelFormatAttribute attrs[] = {
      NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
      NSOpenGLPFAAccelerated,
      NSOpenGLPFAColorSize, 32,
      0};
  NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
  if (!pf) { NSLog(@"[GpuPixelBeauty] 无法创建 NSOpenGLPixelFormat"); return nil; }
  _glContext = [[NSOpenGLContext alloc] initWithFormat:pf shareContext:nil];
  if (!_glContext) { NSLog(@"[GpuPixelBeauty] 无法创建 NSOpenGLContext"); return nil; }
  [_glContext makeCurrentContext];

  // 2. 资源路径(models 人脸模型 + res 美颜贴图)
  GPUPixel::SetResourcePath(std::string(resourcePath.UTF8String));

  // 3. 创建美颜管线: source → reshape(瘦脸大眼) → beauty(磨皮美白) → sink
  _source = SourceRawData::Create();
  _sink = SinkRawData::Create();
  _beauty = BeautyFaceFilter::Create();
  _reshape = FaceReshapeFilter::Create();
  _detector = FaceDetector::Create();
  if (!_source || !_sink || !_beauty || !_reshape) {
    NSLog(@"[GpuPixelBeauty] 创建滤镜失败");
    return nil;
  }
  _source->AddSink(_reshape)->AddSink(_beauty)->AddSink(_sink);
  NSLog(@"[GP] ✅初始化成功(OpenGL+美颜管线) resPath=%@", resourcePath);
  return self;
}

- (void)setSmoothing:(float)smoothing
           whitening:(float)whitening
            faceSlim:(float)faceSlim
             eyeZoom:(float)eyeZoom {
  if (!_glContext) return;
  [_glContext makeCurrentContext];
  // 入参均 0~1(对应滑块 0~100), 内部缩放到 GpuPixel 各自合适范围
  _beauty->SetBlurAlpha(smoothing);              // 磨皮 0~1
  _beauty->SetWhite(whitening * 0.5f);           // 美白 0~0.5
  _reshape->SetFaceSlimLevel(faceSlim * 0.05f);  // 瘦脸 0~0.05
  _reshape->SetEyeZoomLevel(eyeZoom * 0.1f);     // 大眼 0~0.1
}

- (nullable NSData *)processBGRA:(const uint8_t *)data
                           width:(int)width
                          height:(int)height
                          stride:(int)stride
                        outWidth:(int *)outWidth
                       outHeight:(int *)outHeight {
  if (!_glContext || !data) return nil;
  [_glContext makeCurrentContext];

  // 人脸检测(瘦脸/大眼需要 landmarks)
  std::vector<float> landmarks =
      _detector->Detect(data, width, height, stride,
                        GPUPIXEL_MODE_FMT_VIDEO, GPUPIXEL_FRAME_TYPE_BGRA);
  if (!landmarks.empty()) {
    _reshape->SetFaceLandmarks(landmarks);
  }

  // 喂帧 → 管线处理
  _source->ProcessData(data, width, height, stride, GPUPIXEL_FRAME_TYPE_BGRA);

  const uint8_t *rgba = _sink->GetRgbaBuffer();
  int ow = _sink->GetWidth();
  int oh = _sink->GetHeight();
  static int fc = 0;
  if (++fc % 30 == 1) {
    NSLog(@"[GP] frame#%d in=%dx%d landmarks=%zu → out rgba=%p %dx%d",
          fc, width, height, landmarks.size(), (const void *)rgba, ow, oh);
  }
  if (!rgba || ow <= 0 || oh <= 0) return nil;
  if (outWidth) *outWidth = ow;
  if (outHeight) *outHeight = oh;
  return [NSData dataWithBytes:rgba length:(NSUInteger)ow * oh * 4];
}

@end
