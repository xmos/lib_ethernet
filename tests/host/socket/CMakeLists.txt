# Set the minimum required version of CMake
cmake_minimum_required(VERSION 3.20)

# Project name and version
project(l2_socket_host)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)

file(GLOB COMMON_FILES "${CMAKE_CURRENT_LIST_DIR}/shared/*.cpp")

add_executable(socket_send ${CMAKE_CURRENT_LIST_DIR}/send/l2_send.cpp ${COMMON_FILES} )

target_include_directories(socket_send PRIVATE ${CMAKE_CURRENT_LIST_DIR}/shared)

# Link the pthread library (needed for multithreading)
find_package(Threads REQUIRED)
target_link_libraries(socket_send PRIVATE Threads::Threads)


add_executable(socket_send_recv ${CMAKE_CURRENT_LIST_DIR}/send_recv/l2_send_recv.cpp ${COMMON_FILES} )

target_include_directories(socket_send_recv PRIVATE ${CMAKE_CURRENT_LIST_DIR}/shared)

# Link the pthread library (needed for multithreading)
find_package(Threads REQUIRED)
target_link_libraries(socket_send_recv PRIVATE Threads::Threads)
