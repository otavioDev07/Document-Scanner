#ifndef DOCUMENT_DETECTOR_H
#define DOCUMENT_DETECTOR_H

#include <opencv2/opencv.hpp>
#include <vector>
#include <tuple>

using namespace cv;
using namespace std;

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
            float threshMax = 255.0f;
            float medianBlurValue = 9.0f;
            float bilateralFilterValue = 18.0f;
            
            // Parâmetros estritamente calibrados no laboratório de testes
            double contoursApproxEpsilonFactor = 0.05;
            double expectedMaxCosine = 0.45;
            double expectedOptimalMaxCosine = 0.25;
            double expectedAreaFactor = 0.20;
            double areaScaleMinFactor = 0.10;
            double minDistanceFromBorderFactor = 0.0;

            // Filtros de Proporção (Aspect Ratio)
            double minAspectRatio = 1.18;                  // Rejeita formas quadradas/QR codes (~1.0)
            double maxAspectRatio = 6.00;                  // Rejeita faixas/tiras verticais e horizontais anômalas

            // Parâmetros do Hough Probabilístico e Fusão Vetorial
            int houghLinesThreshold = 40;
            int houghLinesMinLineLength = 40;
            int houghLinesMaxLineGap = 15;
            double houghParallelCosine = 0.95;             // Limiar para considerar linhas paralelas na fusão
            double houghIntersectionClusterDistance = 18.0; // Distância máxima para agrupar interseções de cantos
            int houghContourThickness = 2;                  // Espessura do contorno ao desenhar máscara do Hough
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

        PageSplitResult detectGutterAndSplit(const Mat& input,
                                             float minPageWidthRatio = 0.20f,
                                             int blurSize = 5);

    private:
        int imageRotation = 0;

        void findSquares(
                cv::Mat srcGray,
                double scaledWidth,
                double scaledHeight,
                std::vector<PointAreaMaxCosMeanCosWeight> &squares,
                cv::Mat drawimage,
                bool drawContours,
                float weight = 1.0);
    };

}

#endif //DOCUMENT_DETECTOR_H