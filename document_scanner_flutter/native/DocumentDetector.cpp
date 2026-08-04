#include <DocumentDetector.h>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <vector>

using namespace detector;
using namespace cv;
using namespace std;

// ============================================================================
// HELPERS GEOMÉTRICOS E MATEMÁTICOS (Importados do ambiente de testes)
// ============================================================================

static bool compareContourAreas(const std::vector<cv::Point> &contour1,
                                const std::vector<cv::Point> &contour2)
{
    return std::fabs(cv::contourArea(contour1)) >
           std::fabs(cv::contourArea(contour2));
}

static void sortPoints(std::vector<cv::Point> &points)
{
    std::sort(points.begin(), points.end(), [](Point const &a, Point const &b) { return a.y < b.y; });
    std::sort(points.begin(), points.begin() + 2, [](Point const &a, Point const &b) { return a.x < b.x; });
    std::sort(points.begin() + 2, points.end(), [](Point const &a, Point const &b) { return a.x > b.x; });
}

static double angle(cv::Point pt1, cv::Point pt2, cv::Point pt0)
{
    double dx1 = pt1.x - pt0.x;
    double dy1 = pt1.y - pt0.y;
    double dx2 = pt2.x - pt0.x;
    double dy2 = pt2.y - pt0.y;
    return (dx1 * dx2 + dy1 * dy2) /
           sqrt((dx1 * dx1 + dy1 * dy1) * (dx2 * dx2 + dy2 * dy2) + 1e-10);
}

static double lineDirectionCosine(const Vec4i& first, const Vec4i& second) {
    Point2f firstDir(static_cast<float>(first[2] - first[0]), static_cast<float>(first[3] - first[1]));
    Point2f secondDir(static_cast<float>(second[2] - second[0]), static_cast<float>(second[3] - second[1]));

    double firstNorm = norm(firstDir);
    double secondNorm = norm(secondDir);

    if (firstNorm < 1e-6 || secondNorm < 1e-6) return 1.0;

    return fabs((firstDir.x * secondDir.x + firstDir.y * secondDir.y) / (firstNorm * secondNorm));
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
            if (angle(prev, next, curr) <= maxCosineCollinear) {
                current.erase(current.begin() + i);
                changed = true;
                break;
            }
        }
    }
    return current;
}

static bool computeIntersectionPoint2f(const Vec4i& first, const Vec4i& second, Point2f& intersection) {
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

static vector<Point2f> clusterIntersectionPoints2f(const vector<Point2f>& intersections, double maximumDistance) {
    struct Cluster { Point2f sum; int count; };
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

// Usamos um template genérico para acessar as opções nativas sem precisar mexer no .h da classe base
template <typename Opts>
static bool refineCornersWithHough(
    const Mat& binaryImage,
    const vector<Point>& contour,
    vector<Point>& refinedCorners,
    const Opts& options) 
{
    if (options.houghLinesThreshold <= 0) return false;

    Mat contourMask = Mat::zeros(binaryImage.size(), CV_8UC1);
    drawContours(contourMask, vector<vector<Point>>{contour}, -1, Scalar(255), 2, LINE_AA);

    vector<Vec4i> lines;
    HoughLinesP(contourMask, lines, 1.0, CV_PI / 180.0, options.houghLinesThreshold, options.houghLinesMinLineLength, options.houghLinesMaxLineGap);

    vector<Vec4i> mergedLines = mergeCollinearLines(lines, 0.98, 40.0);
    if (mergedLines.size() < 4) return false;

    Rect contourBounds = boundingRect(contour);
    
    // Tratativa de fallback caso a opção nova não exista na struct ainda
    double clusterDist = 18.0; 
    double parallelCos = 0.95;

    int expansion = static_cast<int>(ceil(clusterDist * 3.5));
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
            if (lineDirectionCosine(first, second) >= parallelCos) continue;

            Point2f intersection;
            if (!computeIntersectionPoint2f(first, second, intersection)) continue;
            if (!acceptedBounds.contains(Point(cvRound(intersection.x), cvRound(intersection.y)))) continue;

            intersections.push_back(intersection);
        }
    }

    vector<Point2f> clustered = clusterIntersectionPoints2f(intersections, clusterDist);
    if (clustered.size() != 4) return false;

    refinedCorners.clear();
    refinedCorners.reserve(4);
    for (const Point2f& point : clustered) {
        refinedCorners.push_back(Point(cvRound(point.x), cvRound(point.y)));
    }

    sortPoints(refinedCorners);
    if (!isContourConvex(refinedCorners)) {
        refinedCorners.clear();
        return false;
    }
    return true;
}

static double getContourSortFactor(PointAreaMaxCosMeanCosWeight contour) {
    return std::get<1>(contour) + (double)std::get<4>(contour) * (1 - std::get<2>(contour));
}

static bool sortByArea(PointAreaMaxCosMeanCosWeight contour1, PointAreaMaxCosMeanCosWeight contour2) {
    return (getContourSortFactor(contour1) > getContourSortFactor(contour2));
}

// ============================================================================
// CLASSE DOCUMENT DETECTOR
// ============================================================================

DocumentDetector::DocumentDetector(cv::Mat &bitmap, int resizeThreshold, int imageRotation, double scale) {
    image = bitmap;
    DocumentDetector::resizeThreshold = resizeThreshold;
    DocumentDetector::imageRotation = imageRotation;
    DocumentDetector::scale = scale;
}
DocumentDetector::DocumentDetector(cv::Mat &bitmap, int resizeThreshold, int imageRotation) {
    image = bitmap;
    DocumentDetector::resizeThreshold = resizeThreshold;
    DocumentDetector::imageRotation = imageRotation;
}
DocumentDetector::DocumentDetector(int resizeThreshold, int imageRotation, double scale) {
    DocumentDetector::resizeThreshold = resizeThreshold;
    DocumentDetector::imageRotation = imageRotation;
    DocumentDetector::scale = scale;
}
DocumentDetector::DocumentDetector(int resizeThreshold, int imageRotation) {
    DocumentDetector::resizeThreshold = resizeThreshold;
    DocumentDetector::imageRotation = imageRotation;
}
DocumentDetector::DocumentDetector() {}
DocumentDetector::~DocumentDetector() {}

void DocumentDetector::findSquares(cv::Mat srcGray, double scaledWidth, double scaledHeight,
                                   std::vector<PointAreaMaxCosMeanCosWeight> &squares, cv::Mat drawImage, bool drawContours, float weight)
{
    int marge = static_cast<int>(scaledWidth * options.minDistanceFromBorderFactor) + options.borderSize;
    int safeMargin = marge + 2;

    std::vector<std::vector<cv::Point>> contours;
    vector<Vec4i> hierarchy;
    cv::findContours(srcGray, contours, hierarchy, cv::RETR_TREE, cv::CHAIN_APPROX_SIMPLE);

    std::sort(contours.begin(), contours.end(), compareContourAreas);

    double maxAllowedArea = (scaledWidth - 2 * options.borderSize) * (scaledHeight - 2 * options.borderSize) * 0.95;
    double minAllowedArea = (scaledWidth * scaledHeight) * options.areaScaleMinFactor;

    for (size_t i = 0; i < contours.size(); i++) {
        std::vector<Point> contour = contours[i];
        double perimeter = cv::arcLength(contour, true);
        double area = cv::contourArea(contour);

        if (perimeter < 100 || area < minAllowedArea || area >= maxAllowedArea) continue;

        std::vector<Point> approx;
        cv::approxPolyDP(contour, approx, perimeter * options.contoursApproxEpsilonFactor, true);

        if (approx.size() > 4) {
            approx = clusterAndReducePolygon(approx, 20.0, -0.90);
        }

        bool houghRefined = false;
        vector<Point> houghApproximation;

        // Se falhou o Douglas-Peucker (não achou 4), tenta Hough como fallback imediato
        if (approx.size() != 4) {
            if (refineCornersWithHough(srcGray, contour, houghApproximation, options)) {
                approx = houghApproximation;
                houghRefined = true;
            } else {
                continue;
            }
        }

        // 1. Rechecagem de Área (pós-modificações)
        area = std::abs(cv::contourArea(approx));
        if (area < minAllowedArea || area >= maxAllowedArea) continue;

        // 2. Convexidade
        if (!cv::isContourConvex(approx)) continue;

        // 3. Checagem de Margens Restrita
        bool outOfBounds = false;
        for (const cv::Point &p : approx) {
            if (p.x <= safeMargin || p.x >= scaledWidth - safeMargin || 
                p.y <= safeMargin || p.y >= scaledHeight - safeMargin) {
                outOfBounds = true;
                break;
            }
        }
        if (outOfBounds) continue;

        // 4. Barramento de Aspect Ratio (Proteção contra tiras finas e formas quadradas)
        double side1 = norm(approx[0] - approx[1]);
        double side2 = norm(approx[1] - approx[2]);
        double side3 = norm(approx[2] - approx[3]);
        double side4 = norm(approx[3] - approx[0]);
        double maxSide = max({side1, side2, side3, side4});
        double minSide = min({side1, side2, side3, side4});

        if (minSide < 1e-5) continue;
        double aspectRatio = maxSide / minSide;

        // Assumindo fallback local caso minAspectRatio não tenha sido mapeado na options ainda
        if (aspectRatio < options.minAspectRatio || aspectRatio > options.maxAspectRatio) continue;

        // 5. Verificação de Angulação dos Vértices
        double maxCosine = 0.0;
        double meanCosine = 0.0;
        for (int j = 0; j < 4; j++) {
            double cosine = std::abs(angle(approx[(j + 3) % 4], approx[(j + 1) % 4], approx[j]));
            maxCosine = std::max(maxCosine, cosine);
            meanCosine += cosine;
        }

        // Se o cosseno estourou, tenta refinar com Hough se ainda não foi feito
        if (maxCosine >= options.expectedMaxCosine) {
            if (!houghRefined && refineCornersWithHough(srcGray, contour, houghApproximation, options)) {
                double houghArea = std::abs(cv::contourArea(houghApproximation));
                if (houghArea >= minAllowedArea && houghArea < maxAllowedArea && cv::isContourConvex(houghApproximation)) {
                    double hMaxCosine = 0.0;
                    double hMeanCosine = 0.0;
                    for (int j = 0; j < 4; j++) {
                        double cosine = std::abs(angle(houghApproximation[(j + 3) % 4], houghApproximation[(j + 1) % 4], houghApproximation[j]));
                        hMaxCosine = std::max(hMaxCosine, cosine);
                        hMeanCosine += cosine;
                    }
                    if (hMaxCosine < options.expectedMaxCosine) {
                        approx = houghApproximation;
                        area = houghArea;
                        maxCosine = hMaxCosine;
                        meanCosine = hMeanCosine;
                    } else {
                        continue; // Mesmo com Hough a geometria falhou
                    }
                } else {
                    continue;
                }
            } else {
                continue;
            }
        }

        squares.push_back(std::make_tuple(approx, area, maxCosine, meanCosine / 4.0, weight));

        if (drawContours) {
            cv::polylines(drawImage, approx, true, Scalar(0, 255, 0), 2, 8);
            cv::polylines(drawImage, contour, true, Scalar(255, 0, 0), 1, 8);
        }
    }
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

void correctGamma(const Mat &img, const Mat &dest, const double gamma_) {
    CV_Assert(gamma_ >= 0);
    Mat lookUpTable(1, 256, CV_8U);
    uchar *p = lookUpTable.ptr();
    for (int i = 0; i < 256; ++i)
        p[i] = saturate_cast<uchar>(pow(i / 255.0, gamma_) * 255.0);

    Mat res = img.clone();
    LUT(img, lookUpTable, dest);
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

    for (int i = 0; i < energy.size(); i++) {
        float sum = 0;
        int count = 0;
        for (int j = -smoothRadius; j <= smoothRadius; j++) {
            int idx = i + j;
            if (idx >= 0 && idx < energy.size()) {
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

    Size size = image.size();
    double width = size.width;
    double height = size.height;
    std::vector<PointAreaMaxCosMeanCosWeight> foundSquares;
    int iterration = 0;
    cv::Mat temp1;
    cv::Mat temp2;
    
    if (options.medianBlurValue > 0) {
        medianBlur(image, temp1, options.medianBlurValue);
    } else {
        temp1 = image;
    }

    cv::Mat dilateStruct = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(std::max(1, (int)options.dilateAnchorSize), std::max(1, (int)options.dilateAnchorSize)));
    cv::Mat morphologyStruct = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(std::max(1, (int)options.morphologyAnchorSize), std::max(1, (int)options.morphologyAnchorSize)));
    
    int channelsCount = std::min(image.channels(), 3);
    int i = channelsCount - 1;
    int minI = 0;
    
    if (options.useChannel >= 0) {
        channelsCount = 1;
        i = options.useChannel;
        minI = options.useChannel;
    }

    int weight = 3000000;
    for (i = i; i >= minI; i--) {
        cv::extractChannel(temp1, temp2, i);

        cv::adaptiveThreshold(temp2, edged, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, 71, 2);
        cv::morphologyEx(edged, edged, cv::MORPH_CLOSE, morphologyStruct);
        cv::dilate(edged, edged, dilateStruct);
        
        findSquares(edged, width, height, foundSquares, image, drawContours, (weight--));
        
        if (foundSquares.size() > 0) {
            std::sort(foundSquares.begin(), foundSquares.end(), sortByArea);
            auto firstContour = foundSquares[0];
            if (std::get<2>(firstContour) < options.expectedOptimalMaxCosine && std::get<1>(firstContour) > (width * height * options.expectedAreaFactor)) {
                i = minI;
                break;
            }
        }
        
        iterration++;
        int t = 60;
        
        while (t >= 10) {
            cv::Canny(temp2, edged, t * options.cannyFactor, options.cannyFactor * t * 2);
            cv::dilate(edged, edged, dilateStruct);
            findSquares(edged, width, height, foundSquares, image, drawContours, (weight--));
            
            if (foundSquares.size() > 0) {
                std::sort(foundSquares.begin(), foundSquares.end(), sortByArea);
                auto firstContour = foundSquares[0];
                if (std::get<2>(firstContour) < options.expectedOptimalMaxCosine && std::get<1>(firstContour) > (width * height * options.expectedAreaFactor)) {
                    i = minI;
                    break;
                }
            }
            iterration++;
            t -= 10;
        }
    }

    if (foundSquares.size() > 0) {
        int borderSize = options.borderSize;
        std::vector<std::vector<Point>> result;
        
        for (int i = 0; i < 1; i++) {
            std::vector<Point> points = std::get<0>(foundSquares[i]);
            for (int j = 0; j < points.size(); j++) {
                if (borderSize > 0) {
                    points[j] -= Point(borderSize, borderSize);
                }
                points[j] *= resizeScale * scale;
            }
            sortPoints(points);
            result.push_back(points);
        }
        return result;
    }
    
    return vector<vector<Point>>();
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
        resize(image, resizedBitmap, sizeConfig);
        
        if (borderSize > 0) {
            copyMakeBorder(resizedBitmap, resizedBitmap, borderSize, borderSize, borderSize, borderSize, BORDER_CONSTANT, Scalar(0, 0, 0));
        }
        return resizedBitmap;
    }
    
    if (borderSize > 0) {
        Mat resizedBitmap;
        copyMakeBorder(image, resizedBitmap, borderSize, borderSize, borderSize, borderSize, BORDER_CONSTANT, Scalar(0, 0, 0));
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