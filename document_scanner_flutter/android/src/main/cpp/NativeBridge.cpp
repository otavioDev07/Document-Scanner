#include <jni.h>
#include <android/bitmap.h>
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
