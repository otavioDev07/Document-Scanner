#ifndef DOCUMENT_DETECTOR_H
#define DOCUMENT_DETECTOR_H

#include <opencv2/opencv.hpp>
#include <vector>
#include <string>

using namespace cv;
using namespace std;

namespace detector {

    class DocumentDetector {
    public:
        struct Options {
            int resizeThreshold = 500;
            int borderSize = 10;

            int medianBlurValue = 9;
            int thresholdValue = 160;
            int thresholdMax = 255;

            int morphologyKernelSize = 4;
            int dilateKernelSize = 3;

            double epsilonFactor = 0.05;
            double minAreaFactor = 0.10; 
            double maxAreaFactor = 0.95;

            double expectedMaxCosine = 0.45; 
            double expectedOptimalMaxCosine = 0.25;
            double expectedAreaFactor = 0.20;

            double minAspectRatio = 1.18;
            double maxAspectRatio = 6.00;

            int houghLinesThreshold = 40;
            double houghLinesMinLineLength = 40.0;
            double houghLinesMaxLineGap = 15.0;
            double houghParallelCosine = 0.95;
            
            double houghIntersectionClusterDistance = 18.0;
            int houghContourThickness = 2;
        };

        struct Candidate {
            vector<Point> points;
            double area;
            double maxCosine;
            double meanCosine;
            int weight;
            string source;

            // Score idêntico ao ambiente de testes
            double score() const {
                return (area * (1.0 - maxCosine)) + (static_cast<double>(weight) * 0.01);
            }
        };

        struct PageSplitResult {
            cv::Rect leftPage;
            cv::Rect rightPage;
            bool hasLeft = false;
            bool hasRight = false;
            int gutterX = -1;
            bool foundGutter = false;
        };

        DocumentDetector(cv::Mat &bitmap, int resizeThreshold, int imageRotation, double scale);
        DocumentDetector(cv::Mat &bitmap, int resizeThreshold, int imageRotation);
        DocumentDetector(int resizeThreshold, int imageRotation, double scale);
        DocumentDetector(int resizeThreshold, int imageRotation);
        DocumentDetector();

        virtual ~DocumentDetector();

        vector<vector<cv::Point>> scanPoint();
        vector<vector<cv::Point>> scanPoint(Mat &edged);
        vector<vector<cv::Point>> scanPoint(Mat &edged, Mat& image);
        vector<vector<cv::Point>> scanPoint(Mat &edged, Mat& image, bool drawContours);

        cv::Mat resizeImage();
        cv::Mat resizeImageMax();
        cv::Mat resizeImageToSize(int size);

        PageSplitResult detectGutterAndSplit(const Mat& input, float minPageWidthRatio = 0.20f, int blurSize = 5);

        cv::Mat image;
        cv::Mat resizedImage;

        double resizeScale = 1.0;
        int resizeThreshold = 500;
        double scale = 1.0;

        Options options;

    private:
        int imageRotation = 0;

        vector<Candidate> findSquares(
            const Mat& binaryImage,
            const Options& options,
            int weight,
            const string& source
        );

        bool isExcellentCandidate(
            const vector<Candidate>& candidates,
            int imageWidth,
            int imageHeight,
            const Options& options
        );

        void sortCandidates(vector<Candidate>& candidates);
    };

}

#endif // DOCUMENT_DETECTOR_H