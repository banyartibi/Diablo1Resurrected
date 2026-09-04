cmake_minimum_required(VERSION 3.16)
project(diablo_gdextension LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Find all DevilutionX compiled object files
file(GLOB_RECURSE DVL_OBJECTS
    "${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/Source/CMakeFiles/libdevilutionx.dir/*.o"
)

add_library(diablo SHARED
    src/register_types.cpp
    src/diablo_bridge.cpp
    ${DVL_OBJECTS}
)

target_include_directories(diablo PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/../godot-cpp/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../godot-cpp/gen/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../godot-cpp/gdextension
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/Source
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/Source
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/_deps/sdl2-src/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/_deps/libfmt-src/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/3rdParty/libmpq
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/3rdParty/PKWare
)

target_compile_options(diablo PRIVATE
    -fPIC
    -O3
    -DNDEBUG
)

target_link_libraries(diablo PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../godot-cpp/bin/libgodot-cpp.linux.template_debug.x86_64.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/3rdParty/libsmackerdec/liblibsmackerdec.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/3rdParty/libmpq/liblibmpq.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/3rdParty/PKWare/libPKWare.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/3rdParty/SDL_image/libSDL_image.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/_deps/libpng-build/libpng16.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/_deps/sdl_audiolib-build/libSDL_audiolib.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/_deps/libfmt-build/libfmt.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/_deps/sdl2-build/libSDL2-2.0.so
    ${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/3rdParty/bzip2/libBZip2.so
    z
    /usr/lib/x86_64-linux-gnu/libvulkan.so.1
    pthread
    dl
)

set_target_properties(diablo PROPERTIES
    OUTPUT_NAME "diablo.linux.template_debug.x86_64"
    PREFIX "lib"
    SUFFIX ".so"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../godot_d1_3d/bin"
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "$ORIGIN;${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/_deps/sdl2-build;${CMAKE_CURRENT_SOURCE_DIR}/../DevilutionX/build/3rdParty/bzip2"
)
