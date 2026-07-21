#include <jni.h>
#include <android/bitmap.h>
#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <vector>

#include <opencv2/opencv.hpp>

#include "DocumentDetector.h"
#include "android_utils.h"

namespace {

void throwJava(JNIEnv *env, const char *message) {
    jclass exceptionClass = env->FindClass("java/lang/RuntimeException");
    env->ThrowNew(exceptionClass, message);
}

std::vector<double> readPoints(JNIEnv *env, jdoubleArray values) {
    const jsize length = env->GetArrayLength(values);
    if (length != 8) {
        throw std::invalid_argument("Exactly four x/y points are required");
    }
    std::vector<double> result(8);
    env->GetDoubleArrayRegion(values, 0, length, result.data());
    return result;
}

std::string readString(JNIEnv *env, jstring value) {
    if (value == nullptr) {
        throw std::invalid_argument("Filter name is required");
    }
    const char *characters = env->GetStringUTFChars(value, nullptr);
    if (characters == nullptr) {
        throw std::runtime_error("Unable to read filter name");
    }
    std::string result(characters);
    env->ReleaseStringUTFChars(value, characters);
    return result;
}

}  // namespace

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_br_com_dinheironanota_document_1scanner_1flutter_NativeDocumentProcessor_nativeDetect(
        JNIEnv *env,
        jobject,
        jobject bitmap,
        jint resizeThreshold,
        jdouble areaScaleMinFactor) {
    try {
        cv::Mat source;
        bitmap_to_mat(env, bitmap, source);
        if (env->ExceptionCheck() || source.empty()) {
            return nullptr;
        }

        detector::DocumentDetector detector(source, resizeThreshold, 0);
        detector.options.areaScaleMinFactor = areaScaleMinFactor;
        const auto detected = detector.scanPoint();
        source.release();

        if (detected.empty() || detected.front().size() != 4) {
            return nullptr;
        }

        jdouble output[8];
        for (size_t i = 0; i < 4; ++i) {
            output[i * 2] = detected.front()[i].x;
            output[i * 2 + 1] = detected.front()[i].y;
        }
        jdoubleArray result = env->NewDoubleArray(8);
        env->SetDoubleArrayRegion(result, 0, 8, output);
        return result;
    } catch (const cv::Exception &error) {
        throwJava(env, error.what());
    } catch (const std::exception &error) {
        throwJava(env, error.what());
    } catch (...) {
        throwJava(env, "Unknown native document detection error");
    }
    return nullptr;
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_br_com_dinheironanota_document_1scanner_1flutter_NativeDocumentProcessor_nativeDetectYuv(
        JNIEnv *env,
        jobject,
        jint width,
        jint height,
        jint chromaPixelStride,
        jobject yBuffer,
        jint yRowStride,
        jobject uBuffer,
        jint uRowStride,
        jobject vBuffer,
        jint vRowStride,
        jint rotationDegrees,
        jint resizeThreshold,
        jdouble areaScaleMinFactor) {
    try {
        if (width <= 0 || height <= 0 ||
            env->GetDirectBufferAddress(yBuffer) == nullptr ||
            env->GetDirectBufferAddress(uBuffer) == nullptr ||
            env->GetDirectBufferAddress(vBuffer) == nullptr) {
            throw std::invalid_argument("Camera frame has invalid direct YUV buffers");
        }

        cv::Mat source;
        buffer_to_mat(
                env,
                width,
                height,
                chromaPixelStride,
                yBuffer,
                yRowStride,
                uBuffer,
                uRowStride,
                vBuffer,
                vRowStride,
                source);
        if (source.empty()) {
            return nullptr;
        }

        detector::DocumentDetector detector(source, resizeThreshold, rotationDegrees);
        detector.options.areaScaleMinFactor = areaScaleMinFactor;
        const auto detected = detector.scanPoint();
        source.release();
        if (detected.empty() || detected.front().size() != 4) {
            return nullptr;
        }

        const bool swapsDimensions = rotationDegrees == 90 || rotationDegrees == 270;
        const double orientedWidth = swapsDimensions ? height : width;
        const double orientedHeight = swapsDimensions ? width : height;
        jdouble output[8];
        for (size_t index = 0; index < 4; ++index) {
            output[index * 2] = std::clamp(
                    detected.front()[index].x / orientedWidth,
                    0.0,
                    1.0);
            output[index * 2 + 1] = std::clamp(
                    detected.front()[index].y / orientedHeight,
                    0.0,
                    1.0);
        }
        jdoubleArray result = env->NewDoubleArray(8);
        env->SetDoubleArrayRegion(result, 0, 8, output);
        return result;
    } catch (const cv::Exception &error) {
        throwJava(env, error.what());
    } catch (const std::exception &error) {
        throwJava(env, error.what());
    } catch (...) {
        throwJava(env, "Unknown native YUV detection error");
    }
    return nullptr;
}

extern "C" JNIEXPORT void JNICALL
Java_br_com_dinheironanota_document_1scanner_1flutter_NativeDocumentProcessor_nativeCrop(
        JNIEnv *env,
        jobject,
        jobject sourceBitmap,
        jdoubleArray normalizedPoints,
        jobject outputBitmap) {
    try {
        const std::vector<double> points = readPoints(env, normalizedPoints);

        cv::Mat source;
        bitmap_to_mat(env, sourceBitmap, source);
        if (env->ExceptionCheck() || source.empty()) {
            return;
        }

        AndroidBitmapInfo outputInfo{};
        if (AndroidBitmap_getInfo(env, outputBitmap, &outputInfo) < 0) {
            throw std::runtime_error("Unable to inspect output bitmap");
        }

        const float width = static_cast<float>(source.cols);
        const float height = static_cast<float>(source.rows);
        std::vector<cv::Point2f> sourcePoints{
                {static_cast<float>(points[0] * width), static_cast<float>(points[1] * height)},
                {static_cast<float>(points[2] * width), static_cast<float>(points[3] * height)},
                {static_cast<float>(points[6] * width), static_cast<float>(points[7] * height)},
                {static_cast<float>(points[4] * width), static_cast<float>(points[5] * height)},
        };
        std::vector<cv::Point2f> destinationPoints{
                {0.0f, 0.0f},
                {static_cast<float>(outputInfo.width - 1), 0.0f},
                {0.0f, static_cast<float>(outputInfo.height - 1)},
                {static_cast<float>(outputInfo.width - 1), static_cast<float>(outputInfo.height - 1)},
        };

        cv::Mat cropped = cv::Mat::zeros(
                static_cast<int>(outputInfo.height),
                static_cast<int>(outputInfo.width),
                source.type());
        const cv::Mat transform = cv::getPerspectiveTransform(sourcePoints, destinationPoints);
        cv::warpPerspective(source, cropped, transform, cropped.size());
        mat_to_bitmap(env, cropped, outputBitmap);
        source.release();
        cropped.release();
    } catch (const cv::Exception &error) {
        throwJava(env, error.what());
    } catch (const std::exception &error) {
        throwJava(env, error.what());
    } catch (...) {
        throwJava(env, "Unknown native perspective crop error");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_br_com_dinheironanota_document_1scanner_1flutter_NativeDocumentProcessor_nativeApplyFilter(
        JNIEnv *env,
        jobject,
        jobject sourceBitmap,
        jstring filterName,
        jobject outputBitmap) {
    try {
        const std::string filter = readString(env, filterName);
        cv::Mat source;
        bitmap_to_mat(env, sourceBitmap, source);
        if (env->ExceptionCheck() || source.empty()) {
            return;
        }

        cv::Mat filtered;
        if (filter == "original") {
            source.copyTo(filtered);
        } else if (filter == "grayscale") {
            cv::Mat gray;
            cv::cvtColor(source, gray, cv::COLOR_RGBA2GRAY);
            cv::cvtColor(gray, filtered, cv::COLOR_GRAY2RGBA);
            gray.release();
        } else if (filter == "highContrast") {
            cv::Mat gray;
            cv::Mat contrasted;
            cv::cvtColor(source, gray, cv::COLOR_RGBA2GRAY);
            gray.convertTo(contrasted, -1, 1.55, 8.0);
            cv::cvtColor(contrasted, filtered, cv::COLOR_GRAY2RGBA);
            gray.release();
            contrasted.release();
        } else if (filter == "colorBoost") {
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
            rgb.release();
            contrasted.release();
            hsv.release();
            for (cv::Mat &channel : channels) channel.release();
        } else {
            throw std::invalid_argument("Unsupported native image filter");
        }

        mat_to_bitmap(env, filtered, outputBitmap);
        source.release();
        filtered.release();
    } catch (const cv::Exception &error) {
        throwJava(env, error.what());
    } catch (const std::exception &error) {
        throwJava(env, error.what());
    } catch (...) {
        throwJava(env, "Unknown native image filter error");
    }
}
