#pragma once

#include <opencv2/core.hpp>

#include <array>
#include <string>
#include <vector>

namespace cascade {

struct Result {
    bool valid = false;
    bool found = false;
    double score = 0.0;
    double fftScore = -1.0;
    std::array<cv::Point2f, 4> points{};
    std::string engine = "none";
};

// All point coordinates are in the supplied image's pixel coordinate system.
Result process(const cv::Mat& bgrImage, const std::vector<cv::Point2f>& rdpPoints, double rdpScore);
Result evaluateSharpness(const cv::Mat& bgrImage);

}  // namespace cascade
