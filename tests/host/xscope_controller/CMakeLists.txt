cmake_minimum_required(VERSION 3.5)

project(host_xscope_controller)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)

add_executable(xscope_controller xscope_controller.cpp)

target_include_directories(xscope_controller PRIVATE $ENV{XMOS_TOOL_PATH}/include)

if(CMAKE_SYSTEM_NAME MATCHES Windows)
    target_compile_definitions(xscope_controller PRIVATE _CRT_SECURE_NO_WARNINGS)
    # Ws2_32 library is needed for select() on socket
    target_link_libraries(xscope_controller PRIVATE Ws2_32)
endif()

find_library(XSCOPE_ENDPOINT_LIB NAMES xscope_endpoint.so xscope_endpoint.lib
                                 PATHS $ENV{XMOS_TOOL_PATH}/lib)

target_link_libraries(xscope_controller PRIVATE ${XSCOPE_ENDPOINT_LIB})
