#ifndef DOCUMENT_DETECTOR_H
#define DOCUMENT_DETECTOR_H

#include <opencv2/opencv.hpp>

using namespace cv;
using namespace std;

template <class T>
T& make_ref(T&& x) { return x; }

typedef std::tuple<std::vector<cv::Point>, double, double, double, int> PointAreaMaxCosMeanCosWeight;

namespace detector {

    class DocumentDetector {
    public:

        DocumentDetector(cv::Mat &bitmap, int resizeThreshold, int imageRotation);
        DocumentDetector(cv::Mat &bitmap, int resizeThreshold, int imageRotation, double scale);
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

        cv::Mat image;
        cv::Mat resizedImage;

        double resizeScale = 1.0f;
        int resizeThreshold = 500;
        double scale = 1.0;

        struct DetectOptions {
            int useChannel = -1;
            float borderSize = 10.0f;
            float cannySigmaX = 0.0f;
            float cannyFactor = 2.0f;
            float morphologyAnchorSize = 4.0f;
            float dilateAnchorSize = 3.0f;
            float thresh = 160.0f;
            float threshMax = 256.0f;
            float medianBlurValue = 9.0f;
            float bilateralFilterValue = 18.0f;
            double contoursApproxEpsilonFactor = 0.02;
            double expectedMaxCosine = 0.4;
            double expectedOptimalMaxCosine = 0.3;
            double expectedAreaFactor = 0.20;
            double areaScaleMinFactor = 0.04;
            double minDistanceFromBorderFactor = 0.0;

            int houghLinesThreshold = 0;
            int houghLinesMinLineLength = 55;
            int houghLinesMaxLineGap = 0;
        };

        struct PageSplitResult {
            cv::Rect leftPage;
            cv::Rect rightPage;
            bool hasLeft = false;
            bool hasRight = false;
            int gutterX = -1;
            bool foundGutter = false;
        };
        DetectOptions options;
//        int adapThresholdBlockSize = 0; // 391
//        int adapThresholdC = 0;          // 53
//        int shouldNegate = 0;          // 53
        PageSplitResult detectGutterAndSplit(const Mat& input,
                                      float minPageWidthRatio = 0.20f,
                                      int blurSize = 5);


    private:
        int imageRotation = 0;
        bool isHisEqual = false;


        void preProcess(Mat src, Mat &dst);



        // void findThreshSquares(cv::Mat srcGray, double scaledWidth, double scaledHeight,
                            //    std::vector<std::vector<cv::Point>> &threshSquares);

        // void findCannySquares(
        //         cv::Mat srcGray,
        //         double scaledWidth,
        //         double scaledHeight,
        //         std::vector<std::vector<cv::Point>> &cannySquares,
        //         int indice,
        //         std::vector<int> &indices);
        void findSquares(
                cv::Mat srcGray,
                double scaledWidth,
                double scaledHeight,
                std::vector<PointAreaMaxCosMeanCosWeight> &squares,
                cv::Mat drawimage,
                bool drawContours,
                float weight  = 1.0);

        cv::Mat preprocessedImage(cv::Mat &image, int cannyValue, int blurValue);

        cv::Point choosePoint(cv::Point center, std::vector<cv::Point> &points, int type);

        std::vector<cv::Point> selectPoints(std::vector<cv::Point> points);

        std::vector<cv::Point> sortPointClockwise(std::vector<cv::Point> vector);

        long long pointSideLine(cv::Point &lineP1, cv::Point &lineP2, cv::Point &point);
    };

}


#endif //DOCUMENT_DETECTOR_H
