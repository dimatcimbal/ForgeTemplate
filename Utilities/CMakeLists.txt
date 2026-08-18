# Common_3/Utilities — Log, Math, MemoryTracking, Threading, Timer, the bstrlib/lz4/zstd
# third-party sources, and FileSystem's base stream API. Foundation of the module split; every
# other module depends on this one, directly or transitively.
#
# Genuinely shared across platforms except FileSystem's Unix variant — Utilities/FileSystem/
# contains exactly FileSystem.c (base stream API, both platforms), ToolFileSystem.c (an
# AssetPipeline-only add-on, not built here — see AssetPipeline/CMakeLists.txt), and
# UnixFileSystem.c (Linux-only). FileSystem.c is listed as an explicit single file rather than
# swept in by a directory glob, precisely so it doesn't also pull in those other two.
#
# Every Forge header is reached via paths relative to the including file itself, matching every
# real upstream .vcxproj. No target_include_directories is needed anywhere in this project for
# that reason — it isn't an oversight if you don't see one.

file(GLOB FORGE_UTILITIES_SOURCES
    "${FORGE_ROOT}/Utilities/*.c"
    "${FORGE_ROOT}/Utilities/Log/*.c"
    "${FORGE_ROOT}/Utilities/Math/*.c"
    "${FORGE_ROOT}/Utilities/MemoryTracking/*.c"
    "${FORGE_ROOT}/Utilities/Threading/*.c"
    "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/zstd/common/*.c"
    "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/zstd/decompress/*.c"
)

# buniutil.c/utf8util.c are excluded because upstream excludes them too, not arbitrarily.
file(GLOB _forge_utilities_bstrlib_sources "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/bstrlib/*.c")
list(FILTER _forge_utilities_bstrlib_sources EXCLUDE REGEX "(buniutil|utf8util)\\.c$")

# lz4hc.c is excluded because upstream excludes it too, not arbitrarily.
file(GLOB _forge_utilities_lz4_sources "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/lz4/*.c")
list(FILTER _forge_utilities_lz4_sources EXCLUDE REGEX "lz4hc\\.c$")

list(APPEND FORGE_UTILITIES_SOURCES
    ${_forge_utilities_bstrlib_sources}
    ${_forge_utilities_lz4_sources}
    "${FORGE_ROOT}/Utilities/FileSystem/FileSystem.c")
if(UNIX)
    list(APPEND FORGE_UTILITIES_SOURCES "${FORGE_ROOT}/Utilities/FileSystem/UnixFileSystem.c")

    # huf_decompress_amd64.S (zstd's BMI2 fast-decode path) only applies on Linux/macOS
    # (__GNUC__ && (__linux__ || __APPLE__)), never Windows. enable_language(ASM) is required for
    # CMake to compile a .S file at all.
    enable_language(ASM)
    list(APPEND FORGE_UTILITIES_SOURCES
        "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/zstd/decompress/huf_decompress_amd64.S")
endif()

add_library(Utilities STATIC ${FORGE_UTILITIES_SOURCES})
