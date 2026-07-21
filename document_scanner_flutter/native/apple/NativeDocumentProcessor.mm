#import "NativeDocumentProcessor.h"

#import <UIKit/UIKit.h>
#import <opencv2/opencv.hpp>

#include <algorithm>
#include <cmath>
#include <exception>
#include <vector>

#include "DocumentDetector.h"

namespace {

void imageToMat(UIImage *image, cv::Mat &output) {
  CGImageRef imageRef = image.CGImage;
  const size_t width = CGImageGetWidth(imageRef);
  const size_t height = CGImageGetHeight(imageRef);
  output.create(static_cast<int>(height), static_cast<int>(width), CV_8UC4);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  const CGBitmapInfo bitmapInfo = static_cast<CGBitmapInfo>(
      static_cast<uint32_t>(kCGImageAlphaPremultipliedLast) |
      static_cast<uint32_t>(kCGBitmapByteOrderDefault));
  CGContextRef context = CGBitmapContextCreate(
      output.data,
      width,
      height,
      8,
      output.step[0],
      colorSpace,
      bitmapInfo);
  CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
  CGContextRelease(context);
  CGColorSpaceRelease(colorSpace);
}

UIImage *matToImage(const cv::Mat &image) {
  NSData *data = [NSData dataWithBytes:image.data length:image.step[0] * image.rows];
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
  CGColorSpaceRef colorSpace = image.channels() == 1
      ? CGColorSpaceCreateDeviceGray()
      : CGColorSpaceCreateDeviceRGB();
  const CGBitmapInfo bitmapInfo = static_cast<CGBitmapInfo>(
      static_cast<uint32_t>(image.channels() == 4
                                ? kCGImageAlphaLast
                                : kCGImageAlphaNone) |
      static_cast<uint32_t>(kCGBitmapByteOrderDefault));
  CGImageRef imageRef = CGImageCreate(
      image.cols,
      image.rows,
      8 * image.elemSize1(),
      8 * image.elemSize(),
      image.step[0],
      colorSpace,
      bitmapInfo,
      provider,
      nullptr,
      false,
      kCGRenderingIntentDefault);
  UIImage *result = [UIImage imageWithCGImage:imageRef];
  CGImageRelease(imageRef);
  CGDataProviderRelease(provider);
  CGColorSpaceRelease(colorSpace);
  return result;
}

UIImage *normalizedImage(UIImage *image) {
  if (image.imageOrientation == UIImageOrientationUp && image.scale == 1.0) {
    return image;
  }
  UIGraphicsBeginImageContextWithOptions(image.size, NO, 1.0);
  [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
  UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return normalized ?: image;
}

NSArray<NSDictionary<NSString *, NSNumber *> *> *normalizedCorners(
    const std::vector<cv::Point> &points,
    double width,
    double height) {
  NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *result =
      [NSMutableArray arrayWithCapacity:4];
  for (const cv::Point &point : points) {
    const double x = std::clamp(point.x / width, 0.0, 1.0);
    const double y = std::clamp(point.y / height, 0.0, 1.0);
    [result addObject:@{@"x" : @(x), @"y" : @(y)}];
  }
  return result;
}

NSDictionary<NSString *, id> *errorResult(NSString *code, NSString *message) {
  return @{
    @"errorCode" : code,
    @"errorMessage" : message,
  };
}

}  // namespace

@implementation DSNativeDocumentProcessor

+ (NSString *)openCVVersion {
  return [NSString stringWithUTF8String:CV_VERSION];
}

+ (NSDictionary<NSString *, id> *)detectImageAtPath:(NSString *)imagePath
                                     resizeThreshold:(NSInteger)resizeThreshold
                                  areaScaleMinFactor:(double)areaScaleMinFactor {
  @try {
    UIImage *loaded = [UIImage imageWithContentsOfFile:imagePath];
    if (loaded == nil) {
      return errorResult(@"IMAGE_NOT_FOUND", @"Unable to decode the source image");
    }
    UIImage *image = normalizedImage(loaded);
    cv::Mat source;
    imageToMat(image, source);
    if (source.empty()) {
      return errorResult(@"IMAGE_DECODE_FAILED", @"Decoded image has no pixels");
    }
    detector::DocumentDetector detector(
        source,
        static_cast<int>(resizeThreshold),
        0);
    detector.options.areaScaleMinFactor = areaScaleMinFactor;
    const std::vector<std::vector<cv::Point>> detected = detector.scanPoint();
    const int width = source.cols;
    const int height = source.rows;
    source.release();

    id corners = [NSNull null];
    if (!detected.empty() && detected.front().size() == 4) {
      corners = normalizedCorners(detected.front(), width, height);
    }
    return @{
      @"corners" : corners,
      @"imageWidth" : @(width),
      @"imageHeight" : @(height),
      @"rotationDegrees" : @0,
      @"mirrored" : @NO,
      @"source" : @"static",
    };
  } @catch (NSException *exception) {
    return errorResult(@"NATIVE_DETECTION_FAILED", exception.reason ?: exception.name);
  }
}

+ (nullable NSArray<NSDictionary<NSString *, NSNumber *> *> *)detectPixelBuffer:
    (CVPixelBufferRef)pixelBuffer
                                                               resizeThreshold:
    (NSInteger)resizeThreshold
                                                            areaScaleMinFactor:
    (double)areaScaleMinFactor {
  if (CVPixelBufferGetPixelFormatType(pixelBuffer) != kCVPixelFormatType_32BGRA) {
    return nil;
  }
  CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
  void *base = CVPixelBufferGetBaseAddress(pixelBuffer);
  const int width = static_cast<int>(CVPixelBufferGetWidth(pixelBuffer));
  const int height = static_cast<int>(CVPixelBufferGetHeight(pixelBuffer));
  const size_t stride = CVPixelBufferGetBytesPerRow(pixelBuffer);
  if (base == nullptr || width <= 0 || height <= 0) {
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return nil;
  }

  NSArray<NSDictionary<NSString *, NSNumber *> *> *result = nil;
  try {
    cv::Mat source(height, width, CV_8UC4, base, stride);
    detector::DocumentDetector detector(
        source,
        static_cast<int>(resizeThreshold),
        0);
    detector.options.areaScaleMinFactor = areaScaleMinFactor;
    const std::vector<std::vector<cv::Point>> detected = detector.scanPoint();
    if (!detected.empty() && detected.front().size() == 4) {
      result = normalizedCorners(detected.front(), width, height);
    }
  } catch (...) {
    result = nil;
  }
  CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
  return result;
}

+ (NSDictionary<NSString *, id> *)cropImageAtPath:(NSString *)imagePath
                                           corners:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)corners
                                        outputPath:(NSString *)outputPath
                                maxOutputDimension:(NSInteger)maxOutputDimension
                                       jpegQuality:(NSInteger)jpegQuality {
  @try {
    if (corners.count != 4) {
      return errorResult(@"INVALID_ARGUMENT", @"Exactly four corners are required");
    }
    UIImage *loaded = [UIImage imageWithContentsOfFile:imagePath];
    if (loaded == nil) {
      return errorResult(@"IMAGE_NOT_FOUND", @"Unable to decode the source image");
    }
    UIImage *image = normalizedImage(loaded);
    cv::Mat source;
    imageToMat(image, source);
    if (source.empty()) {
      return errorResult(@"IMAGE_DECODE_FAILED", @"Decoded image has no pixels");
    }

    const float width = static_cast<float>(source.cols);
    const float height = static_cast<float>(source.rows);
    std::vector<cv::Point2f> ordered;
    ordered.reserve(4);
    for (NSDictionary<NSString *, NSNumber *> *corner in corners) {
      const double x = [corner[@"x"] doubleValue];
      const double y = [corner[@"y"] doubleValue];
      if (!std::isfinite(x) || !std::isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
        source.release();
        return errorResult(@"INVALID_ARGUMENT", @"Corner coordinates must be normalized");
      }
      ordered.emplace_back(x * width, y * height);
    }

    const double topWidth = cv::norm(ordered[0] - ordered[1]);
    const double bottomWidth = cv::norm(ordered[3] - ordered[2]);
    const double leftHeight = cv::norm(ordered[0] - ordered[3]);
    const double rightHeight = cv::norm(ordered[1] - ordered[2]);
    int outputWidth = std::max(1, static_cast<int>(std::round((topWidth + bottomWidth) / 2.0)));
    int outputHeight = std::max(1, static_cast<int>(std::round((leftHeight + rightHeight) / 2.0)));
    const int longest = std::max(outputWidth, outputHeight);
    if (maxOutputDimension > 0 && longest > maxOutputDimension) {
      const double scale = maxOutputDimension / static_cast<double>(longest);
      outputWidth = std::max(1, static_cast<int>(std::round(outputWidth * scale)));
      outputHeight = std::max(1, static_cast<int>(std::round(outputHeight * scale)));
    }

    std::vector<cv::Point2f> sourcePoints{
        ordered[0], ordered[1], ordered[3], ordered[2]};
    std::vector<cv::Point2f> destinationPoints{
        {0.0f, 0.0f},
        {static_cast<float>(outputWidth - 1), 0.0f},
        {0.0f, static_cast<float>(outputHeight - 1)},
        {static_cast<float>(outputWidth - 1), static_cast<float>(outputHeight - 1)}};
    cv::Mat cropped = cv::Mat::zeros(outputHeight, outputWidth, source.type());
    const cv::Mat transform = cv::getPerspectiveTransform(sourcePoints, destinationPoints);
    cv::warpPerspective(source, cropped, transform, cropped.size());
    UIImage *output = matToImage(cropped);
    NSData *jpeg = UIImageJPEGRepresentation(
        output,
        std::clamp(jpegQuality, 1L, 100L) / 100.0);
    const BOOL written = [jpeg writeToFile:outputPath atomically:YES];
    source.release();
    cropped.release();
    if (!written) {
      return errorResult(@"WRITE_FAILED", @"Unable to save the cropped image");
    }
    return @{
      @"path" : outputPath,
      @"width" : @(outputWidth),
      @"height" : @(outputHeight),
    };
  } @catch (NSException *exception) {
    return errorResult(@"NATIVE_CROP_FAILED", exception.reason ?: exception.name);
  }
}

+ (NSDictionary<NSString *, id> *)applyFilterAtPath:(NSString *)imagePath
                                               filter:(NSString *)filter
                                           outputPath:(NSString *)outputPath
                                         outputFormat:(NSString *)outputFormat
                                          jpegQuality:(NSInteger)jpegQuality {
  @try {
    UIImage *loaded = [UIImage imageWithContentsOfFile:imagePath];
    if (loaded == nil) {
      return errorResult(@"IMAGE_NOT_FOUND", @"Unable to decode the source image");
    }
    UIImage *image = normalizedImage(loaded);
    cv::Mat source;
    imageToMat(image, source);
    if (source.empty()) {
      return errorResult(@"IMAGE_DECODE_FAILED", @"Decoded image has no pixels");
    }

    cv::Mat filtered;
    if ([filter isEqualToString:@"original"]) {
      source.copyTo(filtered);
    } else if ([filter isEqualToString:@"grayscale"]) {
      cv::Mat gray;
      cv::cvtColor(source, gray, cv::COLOR_RGBA2GRAY);
      cv::cvtColor(gray, filtered, cv::COLOR_GRAY2RGBA);
    } else if ([filter isEqualToString:@"highContrast"]) {
      cv::Mat gray;
      cv::Mat contrasted;
      cv::cvtColor(source, gray, cv::COLOR_RGBA2GRAY);
      gray.convertTo(contrasted, -1, 1.55, 8.0);
      cv::cvtColor(contrasted, filtered, cv::COLOR_GRAY2RGBA);
    } else if ([filter isEqualToString:@"colorBoost"]) {
      cv::Mat rgb;
      cv::Mat contrasted;
      cv::Mat hsv;
      cv::cvtColor(source, rgb, cv::COLOR_RGBA2RGB);
      rgb.convertTo(contrasted, -1, 1.15, 0.0);
      cv::cvtColor(contrasted, hsv, cv::COLOR_RGB2HSV);
      std::vector<cv::Mat> channels;
      cv::split(hsv, channels);
      channels[1].convertTo(channels[1], -1, 1.2, 0.0);
      cv::merge(channels, hsv);
      cv::cvtColor(hsv, rgb, cv::COLOR_HSV2RGB);
      cv::cvtColor(rgb, filtered, cv::COLOR_RGB2RGBA);
    } else {
      source.release();
      return errorResult(@"INVALID_ARGUMENT", @"Unsupported native image filter");
    }

    UIImage *output = matToImage(filtered);
    NSData *encoded = [outputFormat isEqualToString:@"png"]
        ? UIImagePNGRepresentation(output)
        : UIImageJPEGRepresentation(
              output,
              std::clamp(jpegQuality, 1L, 100L) / 100.0);
    const BOOL written = [encoded writeToFile:outputPath atomically:YES];
    const int width = filtered.cols;
    const int height = filtered.rows;
    source.release();
    filtered.release();
    if (!written) {
      return errorResult(@"WRITE_FAILED", @"Unable to save the filtered image");
    }
    return @{
      @"path" : outputPath,
      @"width" : @(width),
      @"height" : @(height),
    };
  } @catch (NSException *exception) {
    return errorResult(@"NATIVE_FILTER_FAILED", exception.reason ?: exception.name);
  }
}

@end
