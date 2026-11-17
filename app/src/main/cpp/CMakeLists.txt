# On-device speech-to-text for captions: whisper.cpp (vendored, v1.9.5) + a small JNI bridge.
cmake_minimum_required(VERSION 3.22)
project(d2pwhisper C CXX)

set(CMAKE_CXX_STANDARD 17)

# ggml is unusably slow unoptimised, so always build it as Release, even for debug APKs.
set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)

set(BUILD_SHARED_LIBS        OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS      OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES   OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER     OFF CACHE BOOL "" FORCE)
set(WHISPER_ALL_WARNINGS     OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE              OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP              OFF CACHE BOOL "" FORCE)
# ARMv8.2 + fp16, but NOT dot-product: the Snapdragon 845 (Pixel 3) lacks it and dies with
# SIGILL on sdot. Phones without fp16 (pre-2018 arm64) aren't supported.
set(GGML_CPU_ARM_ARCH "armv8.2-a+fp16" CACHE STRING "" FORCE)

add_subdirectory(whisper.cpp EXCLUDE_FROM_ALL)

add_library(d2pwhisper SHARED jni.cpp)
target_link_libraries(d2pwhisper PRIVATE whisper log android)
target_compile_options(d2pwhisper PRIVATE -O3 -fvisibility=hidden)
target_link_options(d2pwhisper PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)
