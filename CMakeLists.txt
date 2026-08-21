cmake_minimum_required(VERSION 3.21)

# CMAKE_TOOLCHAIN_FILE must be set (via CMakePresets.json's cacheVariables, one of
# cmake/forge-toolchain-clang-cl.cmake / cmake/forge-toolchain-msvc.cmake) before project() triggers
# compiler detection — a bare `cmake -S . -B build` on Windows with no preset would otherwise silently
# fall through to CMake's own default MSVC auto-detection, which isn't guaranteed to land on the one
# toolset (VS2019 16.11 / MSVC 14.29.x) Common_3/Application/Config.h whitelists. On Linux this check
# plays no role; gcc/clang are found on PATH as normal, no toolchain file needed at all.
if(WIN32 AND NOT CMAKE_TOOLCHAIN_FILE)
    message(FATAL_ERROR
        "No toolchain file set — configure via one of the CMakePresets.json presets "
        "(e.g. `cmake --preset clang-dev`), not a bare `cmake -S . -B build`.")
endif()

project(ForgeTemplate CXX C)

# C++17, not upstream's own C++14 — don't lower this. Renderer's vendored D3D12MemoryAllocator.h
# relies on C++17's *guaranteed* copy elision; under C++14 the same code is a hard compile error
# (clang-cl: "invokes deleted constructor"), not a warning, and can't be suppressed or fixed at the
# source since ForgeSrc is never edited.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(WIN32)
    # /EHs-c- /GR- can't be set via either toolchain file's own CMAKE_CXX_FLAGS_INIT — CMake's own
    # Windows-MSVC.cmake platform module unconditionally appends "/EHsc" after the toolchain file
    # runs, overriding it. add_compile_options() here lands after CMAKE_CXX_FLAGS for real. Also
    # stripped from CMAKE_CXX_FLAGS outright below, to avoid cl.exe's D9025 "overriding" noise on
    # every file.
    string(REPLACE "/EHsc" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    add_compile_options(
        $<$<COMPILE_LANGUAGE:CXX>:/EHs-c->
        $<$<COMPILE_LANGUAGE:CXX>:/GR->
    )
endif()

# /Z7 instead of /Zi for clang-cl's own Debug builds only (CMAKE_CXX_COMPILER_ID is "Clang" for
# clang-cl, "MSVC" for real cl.exe). Same "CMAKE_..._INIT gets overridden later" hazard as the /EHsc
# case above — CMake force-appends "/Zi" after the toolchain file's own "/Z7", so
# add_compile_options() is needed here too to win for real. clang-cl's PDB writer records each TU's
# un-collapsed "../../.." vendored include-chain path rather than canonicalizing it, which can exceed
# Windows' 260-char MAX_PATH purely from its own length — a real CI "path too long" failure. /Z7
# embeds debug info per-object instead of one shared .pdb, avoiding that path-recording step. cl.exe
# keeps /Zi (no such hazard) — this block never touches the msvc toolchain.
if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    add_compile_options(
        $<$<AND:$<COMPILE_LANGUAGE:CXX>,$<CONFIG:Debug>>:/Z7>
        $<$<AND:$<COMPILE_LANGUAGE:C>,$<CONFIG:Debug>>:/Z7>
    )
endif()

# Every module's CMakeLists.txt globs its sources from here rather than each hardcoding its own
# relative "../ForgeSrc/Common_3" — one place to repoint if the vendored checkout ever moves.
set(FORGE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/ForgeSrc/Common_3")

add_subdirectory(Utilities)
add_subdirectory(OS)
add_subdirectory(Renderer)

if(WIN32)
    # cmake/forge-runtime.cmake applies target_link_libraries()/target_link_options() directly to the
    # Renderer target, so it must be included after add_subdirectory(Renderer) creates it, but before
    # any example's own add_subdirectory() needs forge_copy_runtime_dlls()/forge_copy_gpu_data() — a
    # plain include() runs in the including (root) scope, so those functions are already visible to
    # every later add_subdirectory().
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/forge-runtime.cmake")
endif()

# cmake/forge-shaders.cmake compiles Application's own shared FSL shader lists (Screenshot/UI/Fonts)
# once, and defines forge_copy_shared_app_shaders() for each example to pull a copy from. Included
# unconditionally (both platforms branch inside the one file) — unlike forge-runtime.cmake above, it
# doesn't need Renderer to exist first.
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/forge-shaders.cmake")

add_subdirectory(Application)
add_subdirectory(Scripting)
add_subdirectory(Ozz)
add_subdirectory(Animation)
add_subdirectory(AssetPipeline)
add_subdirectory(Examples/01_Transformations)
