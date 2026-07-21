cmake_minimum_required(VERSION 3.22.1)
project(document_scanner_flutter LANGUAGES CXX)

find_package(OpenCV REQUIRED CONFIG)

add_library(
    document_scanner_flutter
    SHARED
    NativeBridge.cpp
    DocumentDetector.cpp
    android_utils.cpp
)

target_include_directories(
    document_scanner_flutter
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(document_scanner_flutter PRIVATE cxx_std_20)
target_compile_options(document_scanner_flutter PRIVATE -Wall -Wextra)

target_link_libraries(
    document_scanner_flutter
    OpenCV::opencv_java4
    android
    jnigraphics
    log
)
