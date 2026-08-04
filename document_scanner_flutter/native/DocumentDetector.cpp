#include "DocumentDetector.h"
#include <algorithm>
#include <cmath>

using namespace detector;
using namespace cv;
using namespace std;

// ============================================================================
// HELPERS GEOMÉTRICOS E MATEMÁTICOS (Fidéis ao Script de Referência)
// ============================================================================

static double angleCosine(const Point& point1, const Point& point2, const Point& vertex) {
    double dx1 = point1.x - vertex.x;
    double dy1 = point1.y - vertex.y;
    double dx2 = point2.x - vertex.x;
    double dy2 = point2.y - vertex.y;

    double dot = dx1 * dx2 + dy1 * dy2;
    double norm1 = std::sqrt(dx1 * dx1 + dy1 * dy1);
    double norm2 = std::sqrt(dx2 * dx2 + dy2 * dy2);

    return dot / (norm1 * norm2 + 1e-10);
}

static double lineDirectionCosine(const Vec4i& first, const Vec4i& second) {
    Point2f firstDirection(static_cast<float>(first[2] - first[0]), static_cast<float>(first[3] - first[1]));
    Point2f secondDirection(static_cast<float>(second[2] - second[0]), static_cast<float>(second[3] - second[1]));

    double firstNorm = norm(firstDirection);
    double secondNorm = norm(secondDirection);

    if (firstNorm < 1e-6 || secondNorm < 1e-6) return 1.0;

    return fabs((firstDirection.x * secondDirection.x + firstDirection.y * secondDirection.y) / (firstNorm * secondNorm));
}

static double pointToLineDistance(Point2f p, Point2f l1, Point2f l2) {
    double num = fabs((l2.x - l1.x) * (l1.y - p.y) - (l1.x - p.x) * (l2.y - l1.y));
    double den = norm(l2 - l1);
    return (den > 1e-6) ? (num / den) : norm(p - l1);
}

static Vec4i mergeTwoLines(const Vec4i& l1, const Vec4i& l2) {
    vector<Point2f> pts = {
        Point2f(l1[0], l1[1]), Point2f(l1[2], l1[3]),
        Point2f(l2[0], l2[1]), Point2f(l2[2], l2[3])
    };
    
    double maxDist = 0;
    Point2f bestP1, bestP2;
    for (int i = 0; i < 4; ++i) {
        for (int j = i + 1; j < 4; ++j) {
            double d = norm(pts[i] - pts[j]);
            if (d > maxDist) {
                maxDist = d;
                bestP1 = pts[i];
                bestP2 = pts[j];
            }
        }
    }
    return Vec4i(cvRound(bestP1.x), cvRound(bestP1.y), cvRound(bestP2.x), cvRound(bestP2.y));
}

static vector<Vec4i> mergeCollinearLines(const vector<Vec4i>& lines, double angleThresh = 0.98, double distThresh = 15.0) {
    vector<Vec4i> merged;
    vector<bool> used(lines.size(), false);

    for (size_t i = 0; i < lines.size(); ++i) {
        if (used[i]) continue;
        Vec4i current = lines[i];
        used[i] = true;
        
        bool mergedInPass;
        do {
            mergedInPass = false;
            for (size_t j = i + 1; j < lines.size(); ++j) {
                if (!used[j]) {
                    if (lineDirectionCosine(current, lines[j]) >= angleThresh) {
                        Point2f p1(current[0], current[1]), p2(current[2], current[3]);
                        Point2f q1(lines[j][0], lines[j][1]), q2(lines[j][2], lines[j][3]);
                        
                        double d1 = pointToLineDistance(q1, p1, p2);
                        double d2 = pointToLineDistance(q2, p1, p2);
                        
                        if (d1 < distThresh && d2 < distThresh) {
                            current = mergeTwoLines(current, lines[j]);
                            used[j] = true;
                            mergedInPass = true;
                        }
                    }
                }
            }
        } while (mergedInPass);
        
        merged.push_back(current);
    }
    return merged;
}

static vector<Point> clusterAndReducePolygon(const vector<Point>& poly, double minDistance = 20.0, double maxCosineCollinear = -0.90) {
    if (poly.size() <= 4) return poly;
    vector<Point> current = poly;
    bool changed = true;

    while (changed && current.size() > 4) {
        changed = false;
        for (size_t i = 0; i < current.size(); i++) {
            size_t nextIdx = (i + 1) % current.size();
            if (norm(current[i] - current[nextIdx]) < minDistance) {
                current[i] = (current[i] + current[nextIdx]) / 2;
                if (nextIdx > i) current.erase(current.begin() + nextIdx);
                else current.erase(current.begin());
                changed = true;
                break;
            }
        }
        if (changed) continue;

        for (size_t i = 0; i < current.size(); i++) {
            Point prev = current[(i + current.size() - 1) % current.size()];
            Point curr = current[i];
            Point next = current[(i + 1) % current.size()];
            if (angleCosine(prev, next, curr) <= maxCosineCollinear) {
                current.erase(current.begin() + i);
                changed = true;
                break;
            }
        }
    }
    return current;
}

static void sortPoints(vector<Point>& points) {
    sort(points.begin(), points.end(), [](const Point& a, const Point& b) {
        return a.y < b.y;
    });
    sort(points.begin(), points.begin() + 2, [](const Point& a, const Point& b) {
        return a.x < b.x;
    });
    sort(points.begin() + 2, points.end(), [](const Point& a, const Point& b) {
        return a.x > b.x;
    });
}

static bool isInsideMargins(const vector<Point>& points, int width, int height, int margin) {
    int safeMargin = margin + 2;
    for (const Point& point : points) {
        if (point.x <= safeMargin || point.x >= width - safeMargin || 
            point.y <= safeMargin || point.y >= height - safeMargin) {
            return false;
        }
    }
    return true;
}

static bool computeLineIntersection(const Vec4i& first, const Vec4i& second, Point2f& intersection) {
    Point2f p(static_cast<float>(first[0]), static_cast<float>(first[1]));
    Point2f r(static_cast<float>(first[2] - first[0]), static_cast<float>(first[3] - first[1]));
    Point2f q(static_cast<float>(second[0]), static_cast<float>(second[1]));
    Point2f s(static_cast<float>(second[2] - second[0]), static_cast<float>(second[3] - second[1]));

    double denominator = static_cast<double>(r.x) * s.y - static_cast<double>(r.y) * s.x;
    if (fabs(denominator) < 1e-6) return false;

    Point2f qMinusP = q - p;
    double t = (static_cast<double>(qMinusP.x) * s.y - static_cast<double>(qMinusP.y) * s.x) / denominator;

    intersection = p + r * static_cast<float>(t);
    return true;
}

static vector<Point2f> clusterIntersectionPoints(const vector<Point2f>& intersections, double maximumDistance) {
    struct Cluster {
        Point2f sum;
        int count;
    };

    vector<Cluster> clusters;

    for (const Point2f& point : intersections) {
        int nearestIndex = -1;
        double nearestDistance = maximumDistance;

        for (size_t index = 0; index < clusters.size(); index++) {
            Point2f center = clusters[index].sum * (1.0f / static_cast<float>(clusters[index].count));
            double distance = norm(point - center);

            if (distance <= nearestDistance) {
                nearestDistance = distance;
                nearestIndex = static_cast<int>(index);
            }
        }

        if (nearestIndex >= 0) {
            clusters[nearestIndex].sum += point;
            clusters[nearestIndex].count++;
        } else {
            clusters.push_back({point, 1});
        }
    }

    vector<Point2f> centers;
    centers.reserve(clusters.size());

    for (const Cluster& cluster : clusters) {
        centers.push_back(cluster.sum * (1.0f / static_cast<float>(cluster.count)));
    }

    return centers;
}

static bool refineCornersWithHough(
    const Mat& binaryImage,
    const vector<Point>& contour,
    const vector<Point>& douglasCorners,
    vector<Point>& refinedCorners,
    const DocumentDetector::Options& options
) {
    if (options.houghLinesThreshold <= 0) return false;

    Mat contourMask = Mat::zeros(binaryImage.size(), CV_8UC1);
    drawContours(contourMask, vector<vector<Point>>{contour}, -1, Scalar(255), options.houghContourThickness, LINE_AA);

    vector<Vec4i> lines;
    HoughLinesP(contourMask, lines, 1.0, CV_PI / 180.0, options.houghLinesThreshold, options.houghLinesMinLineLength, options.houghLinesMaxLineGap);

    vector<Vec4i> mergedLines = mergeCollinearLines(lines, 0.98, 40.0);

    if (mergedLines.size() < 4) return false;

    Rect contourBounds = boundingRect(contour);
    int expansion = static_cast<int>(ceil(options.houghIntersectionClusterDistance * 3.5));
    Rect acceptedBounds(
        max(0, contourBounds.x - expansion), max(0, contourBounds.y - expansion),
        min(binaryImage.cols, contourBounds.x + contourBounds.width + expansion) - max(0, contourBounds.x - expansion),
        min(binaryImage.rows, contourBounds.y + contourBounds.height + expansion) - max(0, contourBounds.x - expansion)
    );

    vector<Point2f> intersections;

    for (size_t firstIndex = 0; firstIndex < mergedLines.size(); firstIndex++) {
        const Vec4i& first = mergedLines[firstIndex];

        for (size_t secondIndex = firstIndex + 1; secondIndex < mergedLines.size(); secondIndex++) {
            const Vec4i& second = mergedLines[secondIndex];
            if (lineDirectionCosine(first, second) >= options.houghParallelCosine) continue;

            Point2f intersection;
            if (!computeLineIntersection(first, second, intersection)) continue;
            if (!acceptedBounds.contains(Point(cvRound(intersection.x), cvRound(intersection.y)))) continue;

            intersections.push_back(intersection);
        }
    }

    vector<Point2f> clustered = clusterIntersectionPoints(intersections, options.houghIntersectionClusterDistance);

    if (clustered.size() != 4) return false;

    refinedCorners.clear();
    refinedCorners.reserve(4);

    for (const Point2f& point : clustered) {
        Point rounded(cvRound(point.x), cvRound(point.y));
        refinedCorners.push_back(rounded);
    }

    sortPoints(refinedCorners);

    if (!isContourConvex(refinedCorners)) {
        refinedCorners.clear();
        return false;
    }

    return true;
}

// ============================================================================
// CLASSE DOCUMENT DETECTOR
// ============================================================================

DocumentDetector::DocumentDetector(cv::Mat &bitmap, int resizeThreshold, int imageRotation, double scale) {
    image = bitmap;
    this->resizeThreshold = resizeThreshold;
    this->imageRotation = imageRotation;
    this->scale = scale;
}

DocumentDetector::DocumentDetector(cv::Mat &bitmap, int resizeThreshold, int imageRotation) {
    image = bitmap;
    this->resizeThreshold = resizeThreshold;
    this->imageRotation = imageRotation;
}

DocumentDetector::DocumentDetector(int resizeThreshold, int imageRotation, double scale) {
    this->resizeThreshold = resizeThreshold;
    this->imageRotation = imageRotation;
    this->scale = scale;
}

DocumentDetector::DocumentDetector(int resizeThreshold, int imageRotation) {
    this->resizeThreshold = resizeThreshold;
    this->imageRotation = imageRotation;
}

DocumentDetector::DocumentDetector() {}
DocumentDetector::~DocumentDetector() {}

vector<DocumentDetector::Candidate> DocumentDetector::findSquares(
    const Mat& binaryImage,
    const Options& options,
    int weight,
    const string& source
) {
    vector<vector<Point>> contours;
    vector<Vec4i> hierarchy;

    findContours(binaryImage.clone(), contours, hierarchy, RETR_TREE, CHAIN_APPROX_SIMPLE);

    sort(contours.begin(), contours.end(), [](const vector<Point>& a, const vector<Point>& b) {
        return fabs(contourArea(a)) > fabs(contourArea(b));
    });

    vector<Candidate> candidates;
    double imageArea = static_cast<double>(binaryImage.cols) * static_cast<double>(binaryImage.rows);
    
    double minimumArea = imageArea * options.minAreaFactor;
    double maximumArea = static_cast<double>(binaryImage.cols - 2 * options.borderSize) *
                        static_cast<double>(binaryImage.rows - 2 * options.borderSize) *
                        options.maxAreaFactor;
    int margin = options.borderSize;

    for (const vector<Point>& contour : contours) {
        double perimeter = arcLength(contour, true);
        double area = fabs(contourArea(contour));

        if (perimeter < 100.0 || area < minimumArea || area >= maximumArea) {
            continue;
        }

        vector<Point> approximation;
        approxPolyDP(contour, approximation, perimeter * options.epsilonFactor, true);

        if (approximation.size() > 4) {
            approximation = clusterAndReducePolygon(approximation, 20.0, -0.90);
        }

        bool houghRefined = false;
        vector<Point> houghApproximation;

        if (approximation.size() != 4) {
            if (refineCornersWithHough(binaryImage, contour, approximation, houghApproximation, options)) {
                approximation = houghApproximation; 
                houghRefined = true;
            } else {
                continue;
            }
        }

        area = fabs(contourArea(approximation));
        
        if (area < minimumArea || area >= maximumArea) continue;
        if (!isContourConvex(approximation)) continue;
        if (!isInsideMargins(approximation, binaryImage.cols, binaryImage.rows, margin)) continue;

        double side1 = norm(approximation[0] - approximation[1]);
        double side2 = norm(approximation[1] - approximation[2]);
        double side3 = norm(approximation[2] - approximation[3]);
        double side4 = norm(approximation[3] - approximation[0]);

        double maxSide = max({side1, side2, side3, side4});
        double minSide = min({side1, side2, side3, side4});

        if (minSide < 1e-5) continue;

        double aspectRatio = maxSide / minSide;
        if (aspectRatio < options.minAspectRatio || aspectRatio > options.maxAspectRatio) continue;

        double maxCosine = 0.0;
        double meanCosine = 0.0;
        for (int index = 0; index < 4; index++) {
            const Point& vertex = approximation[index];
            const Point& previous = approximation[(index + 3) % 4];
            const Point& next = approximation[(index + 1) % 4];
            double cosine = fabs(angleCosine(previous, next, vertex));
            maxCosine = max(maxCosine, cosine);
            meanCosine += cosine;
        }
        meanCosine /= 4.0;

        if (maxCosine >= options.expectedMaxCosine) continue;

        if (!houghRefined) {
            if (refineCornersWithHough(binaryImage, contour, approximation, houghApproximation, options)) {
                double houghArea = fabs(contourArea(houghApproximation));
                
                if (houghArea >= minimumArea && houghArea < maximumArea &&
                    isContourConvex(houghApproximation) &&
                    isInsideMargins(houghApproximation, binaryImage.cols, binaryImage.rows, margin)) 
                {
                    double hSide1 = norm(houghApproximation[0] - houghApproximation[1]);
                    double hSide2 = norm(houghApproximation[1] - houghApproximation[2]);
                    double hSide3 = norm(houghApproximation[2] - houghApproximation[3]);
                    double hSide4 = norm(houghApproximation[3] - houghApproximation[0]);
                    double hMaxSide = max({hSide1, hSide2, hSide3, hSide4});
                    double hMinSide = min({hSide1, hSide2, hSide3, hSide4});

                    if (hMinSide > 1e-5) {
                        double hAspectRatio = hMaxSide / hMinSide;
                        if (hAspectRatio >= options.minAspectRatio && hAspectRatio <= options.maxAspectRatio) {
                            double houghMaxCosine = 0.0;
                            double houghMeanCosine = 0.0;
                            for (int index = 0; index < 4; index++) {
                                const Point& vertex = houghApproximation[index];
                                const Point& previous = houghApproximation[(index + 3) % 4];
                                const Point& next = houghApproximation[(index + 1) % 4];
                                double cosine = fabs(angleCosine(previous, next, vertex));
                                houghMaxCosine = max(houghMaxCosine, cosine);
                                houghMeanCosine += cosine;
                            }
                            houghMeanCosine /= 4.0;

                            if (houghMaxCosine < options.expectedMaxCosine) {
                                approximation = houghApproximation;
                                houghRefined = true;
                                area = houghArea;
                                maxCosine = houghMaxCosine;
                                meanCosine = houghMeanCosine;
                            }
                        }
                    }
                }
            }
        }

        Candidate candidate{
            approximation,
            area,
            maxCosine,
            meanCosine,
            weight,
            houghRefined ? source + " + Hough" : source
        };

        candidates.push_back(candidate);
    }

    return candidates;
}

bool DocumentDetector::isExcellentCandidate(
    const vector<Candidate>& candidates,
    int imageWidth,
    int imageHeight,
    const Options& options
) {
    if (candidates.empty()) return false;
    const Candidate& candidate = candidates.front();
    double imageArea = static_cast<double>(imageWidth) * static_cast<double>(imageHeight);
    return candidate.maxCosine < options.expectedOptimalMaxCosine && candidate.area > imageArea * options.expectedAreaFactor;
}

void DocumentDetector::sortCandidates(vector<Candidate>& candidates) {
    sort(candidates.begin(), candidates.end(), [](const Candidate& a, const Candidate& b) {
        return a.score() > b.score();
    });
}

vector<vector<cv::Point>> DocumentDetector::scanPoint() {
    Mat edged;
    return scanPoint(edged);
}

vector<vector<cv::Point>> DocumentDetector::scanPoint(Mat &edged) {
    resizedImage = resizeImageMax();
    return scanPoint(edged, resizedImage, false);
}

vector<vector<cv::Point>> DocumentDetector::scanPoint(Mat &edged, Mat &image) {
    return scanPoint(edged, image, false);
}

vector<vector<cv::Point>> DocumentDetector::scanPoint(Mat &edged, Mat &image, bool drawContours) {
    if (image.empty()) {
        resizedImage = resizeImageMax();
        image = resizedImage;
    }

    if (imageRotation != 0) {
        switch (imageRotation) {
        case 90:
            rotate(image, image, ROTATE_90_CLOCKWISE);
            break;
        case 180:
            rotate(image, image, ROTATE_180);
            break;
        default:
            rotate(image, image, ROTATE_90_COUNTERCLOCKWISE);
            break;
        }
    }

    Mat blurred;
    medianBlur(image, blurred, options.medianBlurValue);

    Mat morphologyKernel = getStructuringElement(MORPH_RECT, Size(options.morphologyKernelSize, options.morphologyKernelSize));
    Mat dilationKernel = getStructuringElement(MORPH_RECT, Size(options.dilateKernelSize, options.dilateKernelSize));

    vector<Candidate> allCandidates;
    int weight = 1000;
    bool stopSearch = false;

    const vector<string> channelNames = {"Azul", "Verde", "Vermelho"};

    for (int channel = min(blurred.channels(), 3) - 1; channel >= 0 && !stopSearch; channel--) {
        Mat isolatedChannel;
        extractChannel(blurred, isolatedChannel, channel);

        Mat thresholdImage;
        adaptiveThreshold(isolatedChannel, thresholdImage, 255, ADAPTIVE_THRESH_GAUSSIAN_C, THRESH_BINARY, 71, 2);

        Mat closedImage;
        morphologyEx(thresholdImage, closedImage, MORPH_CLOSE, morphologyKernel);

        Mat dilatedThreshold;
        dilate(closedImage, dilatedThreshold, dilationKernel);

        vector<Candidate> thresholdCandidates = findSquares(
            dilatedThreshold,
            options,
            weight--,
            "Threshold " + channelNames[channel]
        );

        allCandidates.insert(allCandidates.end(), thresholdCandidates.begin(), thresholdCandidates.end());
        sortCandidates(allCandidates);

        if (isExcellentCandidate(allCandidates, image.cols, image.rows, options)) {
            stopSearch = true;
            break;
        }

        for (int value = 60; value >= 10 && !stopSearch; value -= 10) {
            int lowerThreshold = value * 2;
            int upperThreshold = value * 4;

            Mat cannyImage;
            Canny(isolatedChannel, cannyImage, lowerThreshold, upperThreshold);

            Mat dilatedCanny;
            dilate(cannyImage, dilatedCanny, dilationKernel);

            string source = "Canny " + to_string(lowerThreshold) + "/" + to_string(upperThreshold) + " " + channelNames[channel];

            vector<Candidate> cannyCandidates = findSquares(
                dilatedCanny,
                options,
                weight--,
                source
            );

            allCandidates.insert(allCandidates.end(), cannyCandidates.begin(), cannyCandidates.end());
            sortCandidates(allCandidates);

            if (isExcellentCandidate(allCandidates, image.cols, image.rows, options)) {
                stopSearch = true;
            }
        }
    }

    sortCandidates(allCandidates);

    if (!allCandidates.empty()) {
        Candidate best = allCandidates.front();
        vector<Point> points = best.points;

        if (options.borderSize > 0) {
            for (size_t j = 0; j < points.size(); j++) {
                points[j] -= Point(options.borderSize, options.borderSize);
            }
        }

        for (size_t j = 0; j < points.size(); j++) {
            points[j] *= resizeScale * scale;
        }

        sortPoints(points);
        return vector<vector<Point>>{points};
    }

    return vector<vector<Point>>();
}

DocumentDetector::PageSplitResult DocumentDetector::detectGutterAndSplit(const Mat& input, float minPageWidthRatio, int blurSize) {
    CV_Assert(!input.empty());

    Mat gray;
    if (input.channels() == 3)
        cvtColor(input, gray, COLOR_BGR2GRAY);
    else
        gray = input.clone();

    GaussianBlur(gray, gray, Size(blurSize, blurSize), 0);

    Mat gradX;
    Sobel(gray, gradX, CV_32F, 1, 0, 3);
    gradX = abs(gradX);

    Mat columnEnergy;
    reduce(gradX, columnEnergy, 0, REDUCE_SUM, CV_32F);

    vector<float> energy(columnEnergy.cols);
    for (int i = 0; i < columnEnergy.cols; i++)
        energy[i] = columnEnergy.at<float>(0, i);

    const int smoothRadius = 15;
    vector<float> smoothEnergy(energy.size(), 0);

    for (size_t i = 0; i < energy.size(); i++) {
        float sum = 0;
        int count = 0;
        for (int j = -smoothRadius; j <= smoothRadius; j++) {
            int idx = static_cast<int>(i) + j;
            if (idx >= 0 && idx < static_cast<int>(energy.size())) {
                sum += energy[idx];
                count++;
            }
        }
        smoothEnergy[i] = sum / count;
    }

    int width = input.cols;
    int searchMin = width * 0.25;
    int searchMax = width * 0.75;
    int gutterX = -1;
    float bestScore = FLT_MAX;

    for (int i = searchMin; i < searchMax; i++) {
        if (smoothEnergy[i] < bestScore) {
            bestScore = smoothEnergy[i];
            gutterX = i;
        }
    }

    DocumentDetector::PageSplitResult result;
    result.gutterX = gutterX;

    if (gutterX < 0) return result;

    int minWidth = static_cast<int>(width * minPageWidthRatio);

    if (gutterX > minWidth) {
        result.leftPage = cv::Rect(0, 0, gutterX, input.rows);
        result.hasLeft = true;
    }
    if (width - gutterX > minWidth) {
        result.rightPage = cv::Rect(gutterX, 0, width - gutterX, input.rows);
        result.hasRight = true;
    }
    result.foundGutter = (gutterX >= 0) && (result.hasLeft || result.hasRight);

    return result;
}

Mat DocumentDetector::resizeImageToSize(int size) {
    int width = image.cols;
    int height = image.rows;
    int borderSize = options.borderSize;

    if (resizeThreshold > 0 && size > resizeThreshold) {
        double widthCoef = width / (double)resizeThreshold;
        double heightCoef = height / (double)resizeThreshold;
        double aspectCoef = std::max(widthCoef, heightCoef);
        resizeScale = aspectCoef;
        width = std::floor(width / aspectCoef);
        height = std::floor(height / aspectCoef);
        Size sizeConfig(width, height);
        Mat resizedBitmap(sizeConfig, CV_8UC3);
        resize(image, resizedBitmap, sizeConfig, 0, 0, INTER_AREA);
        
        if (borderSize > 0) {
            copyMakeBorder(resizedBitmap, resizedBitmap, borderSize, borderSize, borderSize, borderSize, BORDER_CONSTANT, Scalar(255, 0, 255));
        }
        return resizedBitmap;
    }
    
    if (borderSize > 0) {
        Mat resizedBitmap;
        copyMakeBorder(image, resizedBitmap, borderSize, borderSize, borderSize, borderSize, BORDER_CONSTANT, Scalar(255, 0, 255));
        return resizedBitmap;
    }
    return image.clone();
}

Mat DocumentDetector::resizeImage() {
    int width = image.cols;
    int height = image.rows;
    int minSize = min(width, height);
    return resizeImageToSize(minSize);
}

Mat DocumentDetector::resizeImageMax() {
    int width = image.cols;
    int height = image.rows;
    int maxSize = max(width, height);
    return resizeImageToSize(maxSize);
}