cmake_minimum_required(VERSION 3.18)
project(room_mode_native CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

include(FetchContent)
FetchContent_Declare(
  eigen
  GIT_REPOSITORY https://gitlab.com/libeigen/eigen.git
  GIT_TAG 3.4.0
  GIT_SHALLOW TRUE
)
# Eigen's own CMakeLists builds tests/docs we don't want; just make its
# headers available instead of add_subdirectory-ing the whole project.
FetchContent_GetProperties(eigen)
if(NOT eigen_POPULATED)
  FetchContent_Populate(eigen)
endif()

add_library(room_mode_native SHARED
  src/api/room_mode_solver.cpp
)
target_include_directories(room_mode_native PRIVATE
  src/core
  ${eigen_SOURCE_DIR}
)
target_compile_options(room_mode_native PRIVATE -O3)

# Native self-test (box FDM/FEM vs analytical, star FEM vs FDM) -- no Flutter
# or mobile toolchain required, runs on the host directly.
add_executable(room_mode_native_test test/test_main.cpp)
target_include_directories(room_mode_native_test PRIVATE
  src/core
  ${eigen_SOURCE_DIR}
)
target_compile_options(room_mode_native_test PRIVATE -O3)

add_executable(room_mode_api_test test/test_api.cpp)
target_link_libraries(room_mode_api_test PRIVATE room_mode_native)
target_include_directories(room_mode_api_test PRIVATE src/core)

enable_testing()
add_test(NAME room_mode_native_test COMMAND room_mode_native_test)
add_test(NAME room_mode_api_test COMMAND room_mode_api_test)
