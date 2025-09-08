cmake_minimum_required(VERSION 3.23)
project(h264_qpblock)

set(CMAKE_CXX_STANDARD 14)

set(SOURCE_FILES
        main.cpp
        parseOptUtils.h
        parseOptUtils.cpp
        decoder.h
        decoder.cpp
        encoder.h
        encoder.cpp
)

# ✅ 使用新版本 FFmpeg/x264 安装路径
include_directories(/usr/local/include)
link_directories(/usr/local/lib)

# ✅ 添加可执行文件
add_executable(h264_qpblock ${SOURCE_FILES})

# ✅ 一次性写入所有需要的库
target_link_libraries(h264_qpblock
    x264
    avformat
    avcodec
    avutil
    swscale
    swresample
    avdevice
    pthread
    dl
)
