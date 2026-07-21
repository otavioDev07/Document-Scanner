#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

@interface DSNativeDocumentProcessor : NSObject

+ (NSString *)openCVVersion;

+ (NSDictionary<NSString *, id> *)detectImageAtPath:(NSString *)imagePath
                                     resizeThreshold:(NSInteger)resizeThreshold
                                  areaScaleMinFactor:(double)areaScaleMinFactor;

+ (nullable NSArray<NSDictionary<NSString *, NSNumber *> *> *)detectPixelBuffer:
    (CVPixelBufferRef)pixelBuffer
                                                               resizeThreshold:
    (NSInteger)resizeThreshold
                                                            areaScaleMinFactor:
    (double)areaScaleMinFactor;

+ (NSDictionary<NSString *, id> *)cropImageAtPath:(NSString *)imagePath
                                           corners:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)corners
                                         outputPath:(NSString *)outputPath
                                 maxOutputDimension:(NSInteger)maxOutputDimension
                                       jpegQuality:(NSInteger)jpegQuality;

+ (NSDictionary<NSString *, id> *)applyFilterAtPath:(NSString *)imagePath
                                               filter:(NSString *)filter
                                           outputPath:(NSString *)outputPath
                                         outputFormat:(NSString *)outputFormat
                                          jpegQuality:(NSInteger)jpegQuality;

@end

NS_ASSUME_NONNULL_END
