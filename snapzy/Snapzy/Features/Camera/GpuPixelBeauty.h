//
//  GpuPixelBeauty.h
//  Snapzy (靓相 Shotlit)
//
//  Objective-C bridge to the GpuPixel C++ engine (pixpark/gpupixel).
//  专业美颜引擎桥接: 磨皮/美白/瘦脸/大眼, 输入 BGRA 帧 → 输出 RGBA 帧。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GpuPixelBeauty : NSObject

/// 初始化(建 OpenGL 上下文 + 美颜管线)。resourcePath 指向含 models/ 与 res/ 的目录。
- (nullable instancetype)initWithResourcePath:(NSString *)resourcePath;

/// 设置美颜参数(全部 0~1)。smoothing 磨皮 / whitening 美白 / faceSlim 瘦脸 / eyeZoom 大眼。
- (void)setSmoothing:(float)smoothing
           whitening:(float)whitening
            faceSlim:(float)faceSlim
             eyeZoom:(float)eyeZoom;

/// 处理一帧 BGRA(摄像头格式), 返回处理后的 RGBA 数据(width*height*4)。失败返回 nil。
- (nullable NSData *)processBGRA:(const uint8_t *)data
                           width:(int)width
                          height:(int)height
                          stride:(int)stride
                        outWidth:(int *)outWidth
                       outHeight:(int *)outHeight;

@end

NS_ASSUME_NONNULL_END
