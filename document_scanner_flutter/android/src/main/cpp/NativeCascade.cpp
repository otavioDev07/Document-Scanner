#include "NativeCascade.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <numeric>

#include <opencv2/imgproc.hpp>

namespace cascade {
namespace {

constexpr double kRdpEarlyExit = 0.30;
constexpr double kHoughEarlyExit = 0.28;
constexpr double kFallbackLock = 0.22;
constexpr double kConsensusIou = 0.80;
constexpr double kFftCutoff = 0.222;
constexpr double kWatershedMaxArea = 0.90;

Result rejected(std::string engine) {
    Result result;
    result.engine = std::move(engine);
    return result;
}

Result candidate(const std::array<cv::Point2f, 4>& points, double score, std::string engine) {
    Result result;
    result.found = true;
    result.points = points;
    result.score = score;
    result.engine = std::move(engine);
    return result;
}

std::array<cv::Point2f, 4> orderPoints(std::array<cv::Point2f, 4> points) {
    cv::Point2f center;
    for (const auto& point : points) center += point;
    center *= 0.25F;
    std::sort(points.begin(), points.end(), [&center](const cv::Point2f& first, const cv::Point2f& second) {
        return std::atan2(first.y - center.y, first.x - center.x) <
               std::atan2(second.y - center.y, second.x - center.x);
    });
    const auto topLeft = std::min_element(points.begin(), points.end(), [](const cv::Point2f& first, const cv::Point2f& second) {
        return first.x + first.y < second.x + second.y;
    });
    std::rotate(points.begin(), topLeft, points.end());
    return points;
}

double geometryScore(const std::array<cv::Point2f, 4>& points, const cv::Size& size) {
    const double imageArea = static_cast<double>(size.area());
    if (imageArea <= 0.0) return 0.0;
    std::vector<cv::Point2f> contour(points.begin(), points.end());
    const double relativeArea = std::abs(cv::contourArea(contour)) / imageArea;
    double maxCosine = 0.0;
    for (int index = 0; index < 4; ++index) {
        const cv::Point2f first = points[(index + 3) % 4] - points[index];
        const cv::Point2f second = points[(index + 1) % 4] - points[index];
        const double normProduct = cv::norm(first) * cv::norm(second);
        if (normProduct > 1e-5) maxCosine = std::max(maxCosine, std::abs(first.dot(second) / normProduct));
    }
    return relativeArea * (1.0 - maxCosine);
}

std::array<int, 4> linePoints(const cv::Vec2f& line) {
    const float rho = line[0];
    const float theta = line[1];
    const float cosine = std::cos(theta);
    const float sine = std::sin(theta);
    const float x0 = cosine * rho;
    const float y0 = sine * rho;
    return {
        static_cast<int>(x0 + 1000.0F * -sine), static_cast<int>(y0 + 1000.0F * cosine),
        static_cast<int>(x0 - 1000.0F * -sine), static_cast<int>(y0 - 1000.0F * cosine),
    };
}

bool isPerpendicular(const std::array<int, 4>& first, const std::array<int, 4>& second) {
    const cv::Point2d firstVector(first[0] - first[2], first[1] - first[3]);
    const cv::Point2d secondVector(second[0] - second[2], second[1] - second[3]);
    const double divisor = cv::norm(firstVector) * cv::norm(secondVector);
    return divisor > 1e-9 && std::abs(firstVector.dot(secondVector) / divisor) <= 0.3;
}

bool intersection(const std::array<int, 4>& first, const std::array<int, 4>& second, cv::Point2f& point) {
    const double denominator1 = (first[0] - first[2]) == 0 ? 0.0001 : first[0] - first[2];
    const double denominator2 = (second[0] - second[2]) == 0 ? 0.0001 : second[0] - second[2];
    const double slope1 = (first[1] - first[3]) / denominator1;
    const double slope2 = (second[1] - second[3]) / denominator2;
    if (std::abs(slope1 - slope2) < 1e-9) return false;
    const double intercept1 = slope1 * -first[0] + first[1];
    const double intercept2 = slope2 * -second[0] + second[1];
    const int x = static_cast<int>((intercept2 - intercept1) / (slope1 - slope2));
    point = cv::Point2f(static_cast<float>(x), static_cast<float>(static_cast<int>(x * slope1 + intercept1)));
    return true;
}

Result runHough(const cv::Mat& image) {
    cv::Mat gray;
    if (image.channels() == 1) gray = image;
    else cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
    const cv::Mat kernel = cv::Mat::ones(8, 8, CV_8U);
    cv::Mat morph;
    cv::dilate(gray, morph, kernel, cv::Point(-1, -1), 11);
    cv::erode(morph, morph, kernel, cv::Point(-1, -1), 11);

    for (int attempt = 0; attempt < 3; ++attempt) {
        cv::Mat canny;
        cv::Canny(morph, canny, 60 - attempt * 20, 130 - attempt * 20, 3);
        std::vector<cv::Vec2f> horizontal;
        std::vector<cv::Vec2f> vertical;
        const double radians = CV_PI / 180.0;
        cv::HoughLines(canny, horizontal, 1, radians, 25, 3, 0,
                       (90 - attempt * 6) * radians, (100 + attempt * 6) * radians);
        cv::HoughLines(canny, vertical, 1, radians, 25, 3, 0,
                       (-10 - attempt * 6) * radians, (5 + attempt * 6) * radians);
        horizontal.resize(std::min<size_t>(horizontal.size(), 4));
        vertical.resize(std::min<size_t>(vertical.size(), 4));

        std::array<std::vector<cv::Point2f>, 4> buckets;
        for (const auto& horizontalLine : horizontal) {
            const auto first = linePoints(horizontalLine);
            for (const auto& verticalLine : vertical) {
                const auto second = linePoints(verticalLine);
                cv::Point2f point;
                if (!isPerpendicular(first, second) || !intersection(first, second, point)) continue;
                const int quadrant = point.x < image.cols / 2 ? (point.y < image.rows / 2 ? 0 : 3)
                                                              : (point.y < image.rows / 2 ? 1 : 2);
                buckets[quadrant].push_back(point);
            }
        }
        if (std::any_of(buckets.begin(), buckets.end(), [](const auto& bucket) { return bucket.empty(); })) continue;
        std::array<cv::Point2f, 4> points;
        for (size_t index = 0; index < buckets.size(); ++index) {
            const cv::Point2f sum = std::accumulate(buckets[index].begin(), buckets[index].end(), cv::Point2f());
            points[index] = sum * (1.0F / static_cast<float>(buckets[index].size()));
        }
        for (auto& point : points) {
            point.x = static_cast<float>(static_cast<int>(point.x));
            point.y = static_cast<float>(static_cast<int>(point.y));
        }
        return candidate(points, geometryScore(points, image.size()), "native_hough");
    }
    return rejected("native_hough");
}

cv::Mat largestComponentMask(const cv::Mat& binary) {
    cv::Mat labels;
    const int count = cv::connectedComponents(binary, labels);
    if (count <= 1) return cv::Mat::zeros(binary.size(), CV_8U);
    std::vector<int> sizes(count, 0);
    for (int row = 0; row < labels.rows; ++row) {
        const int* values = labels.ptr<int>(row);
        for (int column = 0; column < labels.cols; ++column) ++sizes[values[column]];
    }
    const int largest = static_cast<int>(std::distance(sizes.begin() + 1, std::max_element(sizes.begin() + 1, sizes.end()))) + 1;
    cv::Mat result = labels == largest;
    return result;
}

Result runWatershed(const cv::Mat& image) {
    cv::Mat bgr;
    if (image.channels() == 1) cv::cvtColor(image, bgr, cv::COLOR_GRAY2BGR);
    else bgr = image;
    cv::Mat resized;
    cv::resize(bgr, resized, cv::Size(), 0.5, 0.5, cv::INTER_AREA);
    cv::Mat gray, blurred, binary, closed;
    cv::cvtColor(resized, gray, cv::COLOR_BGR2GRAY);
    cv::medianBlur(gray, blurred, 7);
    cv::adaptiveThreshold(blurred, binary, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, 45, 2);
    const cv::Mat kernel = cv::Mat::ones(3, 3, CV_8U);
    cv::erode(binary, closed, kernel, cv::Point(-1, -1), 2);
    cv::morphologyEx(closed, closed, cv::MORPH_CLOSE, kernel, cv::Point(-1, -1), 2);
    cv::Mat foreground = largestComponentMask(closed);
    cv::morphologyEx(foreground, foreground, cv::MORPH_CLOSE, kernel, cv::Point(-1, -1), 8);
    cv::Mat inverseForeground, background;
    cv::compare(foreground, 0, inverseForeground, cv::CMP_EQ);
    background = largestComponentMask(inverseForeground);
    cv::erode(background, background, kernel, cv::Point(-1, -1), 20);
    cv::Mat combined, unknown;
    cv::bitwise_or(foreground, background, combined);
    cv::bitwise_not(combined, unknown);

    cv::Mat markers;
    cv::connectedComponents(foreground, markers);
    markers.setTo(0, unknown == 255);
    cv::add(markers, 1, markers, markers > 0);
    markers.setTo(1, background == 255);
    cv::watershed(resized, markers);

    std::vector<int> counts(2, 0);
    int maxLabel = 1;
    for (int row = 0; row < markers.rows; ++row) {
        const int* values = markers.ptr<int>(row);
        for (int column = 0; column < markers.cols; ++column) {
            if (values[column] > maxLabel) maxLabel = values[column];
        }
    }
    counts.resize(maxLabel + 1, 0);
    for (int row = 0; row < markers.rows; ++row) {
        const int* values = markers.ptr<int>(row);
        for (int column = 0; column < markers.cols; ++column) if (values[column] > 1) ++counts[values[column]];
    }
    const auto labelIt = std::max_element(counts.begin() + std::min<size_t>(2, counts.size()), counts.end());
    if (labelIt == counts.end() || *labelIt <= static_cast<double>(markers.total()) * 0.25) return rejected("native_watershed");
    const int label = static_cast<int>(std::distance(counts.begin(), labelIt));
    cv::Mat mask = markers == label;
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    if (contours.empty()) return rejected("native_watershed");
    const auto largest = std::max_element(contours.begin(), contours.end(), [](const auto& first, const auto& second) {
        return cv::contourArea(first) < cv::contourArea(second);
    });
    std::vector<cv::Point> hull, polygon;
    cv::convexHull(*largest, hull);
    const double perimeter = cv::arcLength(hull, true);
    double epsilon = 0.02;
    cv::approxPolyDP(hull, polygon, epsilon * perimeter, true);
    while (polygon.size() > 6 && epsilon < 1.0) {
        epsilon += 0.02;
        cv::approxPolyDP(hull, polygon, epsilon * perimeter, true);
    }
    if (polygon.size() < 3 || polygon.size() > 6) return rejected("native_watershed");
    const cv::RotatedRect rect = cv::minAreaRect(polygon);
    const double rectArea = rect.size.area();
    if (rectArea <= 0.0 || cv::contourArea(polygon) / rectArea < 0.7) return rejected("native_watershed");
    cv::Point2f box[4];
    rect.points(box);
    std::array<cv::Point2f, 4> points;
    for (int index = 0; index < 4; ++index) points[index] = cv::Point2f(static_cast<int>(box[index].x * 2.0F), static_cast<int>(box[index].y * 2.0F));
    std::vector<cv::Point2f> pointVector(points.begin(), points.end());
    const double relativeArea = std::abs(cv::contourArea(pointVector)) / static_cast<double>(image.total());
    if (relativeArea >= kWatershedMaxArea) return rejected("native_watershed_area_guard");
    return candidate(points, geometryScore(points, image.size()), "native_watershed");
}

double intersectionOverUnion(const std::array<cv::Point2f, 4>& first, const std::array<cv::Point2f, 4>& second) {
    const auto orderedFirst = orderPoints(first);
    const auto orderedSecond = orderPoints(second);
    std::vector<cv::Point2f> firstPolygon(orderedFirst.begin(), orderedFirst.end());
    std::vector<cv::Point2f> secondPolygon(orderedSecond.begin(), orderedSecond.end());
    const double firstArea = std::abs(cv::contourArea(firstPolygon));
    const double secondArea = std::abs(cv::contourArea(secondPolygon));
    if (firstArea == 0.0 || secondArea == 0.0) return 0.0;
    std::vector<cv::Point2f> intersection;
    const double intersectionArea = cv::intersectConvexConvex(firstPolygon, secondPolygon, intersection);
    const double unionArea = firstArea + secondArea - intersectionArea;
    return unionArea > 0.0 ? intersectionArea / unionArea : 0.0;
}

Result arbitrate(const std::vector<Result>& candidates) {
    std::vector<const Result*> valid;
    for (const auto& item : candidates) if (item.found) valid.push_back(&item);
    for (size_t first = 0; first < valid.size(); ++first) {
        for (size_t second = first + 1; second < valid.size(); ++second) {
            if (intersectionOverUnion(valid[first]->points, valid[second]->points) >= kConsensusIou) {
                const auto firstPoints = orderPoints(valid[first]->points);
                const auto secondPoints = orderPoints(valid[second]->points);
                std::array<cv::Point2f, 4> blended;
                for (int index = 0; index < 4; ++index) blended[index] = cv::Point2f(
                    static_cast<int>((firstPoints[index].x + secondPoints[index].x) / 2.0F),
                    static_cast<int>((firstPoints[index].y + secondPoints[index].y) / 2.0F));
                return candidate(blended, std::max(valid[first]->score, valid[second]->score),
                                 "consensus_" + valid[first]->engine + "_" + valid[second]->engine);
            }
        }
    }
    if (valid.empty()) return rejected("arbiter");
    const Result* best = *std::max_element(valid.begin(), valid.end(), [](const Result* first, const Result* second) {
        return first->score < second->score;
    });
    return best->score >= kFallbackLock ? *best : rejected("arbiter_fallback_lock");
}

double fftScore(const cv::Mat& image) {
    cv::Mat gray;
    if (image.channels() == 1) gray = image;
    else cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
    cv::Mat floatGray;
    // NumPy fft2 promotes the Python pipeline's float32 image to complex128.
    // Keep the same precision so the 0.222 decision boundary is unchanged.
    gray.convertTo(floatGray, CV_64F, 1.0 / 255.0);
    cv::Mat spectrum;
    cv::dft(floatGray, spectrum, cv::DFT_COMPLEX_OUTPUT);
    const int centerX = spectrum.cols / 2;
    const int centerY = spectrum.rows / 2;
    // Python's symmetric half-open slice drops one pixel for an odd requested
    // size: [center - n//2 : center + n//2]. Mirror that exact extent.
    const int cropWidth = 2 * (static_cast<int>(spectrum.cols * 0.6) / 2);
    const int cropHeight = 2 * (static_cast<int>(spectrum.rows * 0.6) / 2);
    const cv::Rect first(centerX - cropWidth / 2, centerY - cropHeight / 2, cropWidth, cropHeight);
    cv::Mat magnitude(first.size(), CV_64F);
    // fftshift is sampled lazily: copying only the 60% central window avoids a full-size shifted spectrum.
    for (int row = 0; row < first.height; ++row) {
        double* output = magnitude.ptr<double>(row);
        for (int column = 0; column < first.width; ++column) {
            const int sourceY = (first.y + row + spectrum.rows / 2) % spectrum.rows;
            const int sourceX = (first.x + column + spectrum.cols / 2) % spectrum.cols;
            const cv::Vec2d value = spectrum.at<cv::Vec2d>(sourceY, sourceX);
            output[column] = std::log1p(std::sqrt(value[0] * value[0] + value[1] * value[1])) * 255.0;
        }
    }
    double minimum, maximum;
    cv::minMaxLoc(magnitude, &minimum, &maximum);
    if (maximum == minimum) return 0.0;
    return cv::mean((magnitude - minimum) / (maximum - minimum))[0];
}

}  // namespace

Result evaluateSharpness(const cv::Mat& bgrImage) {
    Result result;
    result.fftScore = fftScore(bgrImage);
    result.valid = result.fftScore > kFftCutoff;
    return result;
}

Result process(const cv::Mat& bgrImage, const std::vector<cv::Point2f>& rdpPoints, double rdpScore) {
    Result rdp = rejected("cpp_rdp_hough");
    if (rdpPoints.size() == 4) {
        std::copy_n(rdpPoints.begin(), 4, rdp.points.begin());
        rdp.found = true;
        rdp.score = rdpScore;
    }
    Result selected;
    if (rdp.found && rdp.score >= kRdpEarlyExit) {
        selected = rdp;
    } else {
        const Result hough = runHough(bgrImage);
        selected = hough.found && hough.score >= kHoughEarlyExit
            ? hough
            : arbitrate({rdp, hough, runWatershed(bgrImage)});
    }
    if (!selected.found) return rejected(selected.engine);
    selected.points = orderPoints(selected.points);
    const auto points = selected.points;
    const float width = std::max(cv::norm(points[2] - points[3]), cv::norm(points[1] - points[0]));
    const float height = std::max(cv::norm(points[1] - points[2]), cv::norm(points[0] - points[3]));
    const int outputWidth = std::max(static_cast<int>(width), 1);
    const int outputHeight = std::max(static_cast<int>(height), 1);
    const std::array<cv::Point2f, 4> destination{{
        {0.0F, 0.0F}, {static_cast<float>(outputWidth - 1), 0.0F},
        {static_cast<float>(outputWidth - 1), static_cast<float>(outputHeight - 1)}, {0.0F, static_cast<float>(outputHeight - 1)},
    }};
    cv::Mat transform = cv::getPerspectiveTransform(points.data(), destination.data());
    cv::Mat warped;
    cv::warpPerspective(bgrImage, warped, transform, cv::Size(outputWidth, outputHeight));
    selected.fftScore = fftScore(warped);
    if (selected.fftScore <= kFftCutoff) {
        Result failure = rejected("fft_rejected");
        failure.fftScore = selected.fftScore;
        return failure;
    }
    selected.valid = true;
    return selected;
}

}  // namespace cascade
