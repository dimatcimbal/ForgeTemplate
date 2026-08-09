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
# Every Forge header is reached via paths relative to the including file itself (e.g.
# Utilities/Threading/ThreadSystem.c includes "../../Utilities/Interfaces/IFileSystem.h") —
# confirmed against the real upstream .vcxproj files, none of which set an
# AdditionalIncludeDirectories at all. No target_include_directories is needed here for that
# reason; it isn't an oversight.

file(GLOB FORGE_UTILITIES_SOURCES
    "${FORGE_ROOT}/Utilities/*.c"
    "${FORGE_ROOT}/Utilities/Log/*.c"
    "${FORGE_ROOT}/Utilities/Math/*.c"
    "${FORGE_ROOT}/Utilities/MemoryTracking/*.c"
    "${FORGE_ROOT}/Utilities/Threading/*.c"
    "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/zstd/common/*.c"
    "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/zstd/decompress/*.c"
)

# bstrlib and lz4 each contain one extra file upstream itself never compiles (confirmed: OS.vcxproj
# and every other real .vcxproj referencing these directories omit them too — not a
# platform-specific or template-specific exclusion).
file(GLOB _forge_utilities_bstrlib_sources "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/bstrlib/*.c")
list(FILTER _forge_utilities_bstrlib_sources EXCLUDE REGEX "(buniutil|utf8util)\\.c$")
list(APPEND FORGE_UTILITIES_SOURCES ${_forge_utilities_bstrlib_sources})

file(GLOB _forge_utilities_lz4_sources "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/lz4/*.c")
list(FILTER _forge_utilities_lz4_sources EXCLUDE REGEX "lz4hc\\.c$")
list(APPEND FORGE_UTILITIES_SOURCES ${_forge_utilities_lz4_sources})

list(APPEND FORGE_UTILITIES_SOURCES "${FORGE_ROOT}/Utilities/FileSystem/FileSystem.c")
if(UNIX)
    list(APPEND FORGE_UTILITIES_SOURCES "${FORGE_ROOT}/Utilities/FileSystem/UnixFileSystem.c")

    # zstd/decompress/huf_decompress.c's own fast BMI2 decode path (HUF_decompress4X{1,2}_
    # usingDTable_internal_fast_asm_loop) is real GNU-assembler-syntax code split into a companion
    # huf_decompress_amd64.S, referenced only when zstd's own portability_macros.h's
    # ZSTD_ENABLE_ASM_X86_64_BMI2 evaluates true — which requires __GNUC__ *and* __linux__/__APPLE__
    # (confirmed directly against that header), never true on Windows (MSVC/clang-cl define neither),
    # so this was genuinely invisible on every Windows build so far. Only surfaces at final-executable
    # link time, same "static libs never resolve external symbols until a real EXE link happens"
    # pattern as gotcha #5 in build-agent.md — confirmed directly: Examples/01_Transformations is the
    # very first real Linux add_executable in this template (every earlier Linux configure only ever
    # built libraries), so no prior Linux build had a link step that could have caught this.
    # enable_language(ASM) makes CMake recognize the .S extension and hand it to the C compiler
    # (gcc/clang both accept GNU-syntax .S directly, no separate assembler needed).
    enable_language(ASM)
    list(APPEND FORGE_UTILITIES_SOURCES
        "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/zstd/decompress/huf_decompress_amd64.S")
endif()

add_library(Utilities STATIC ${FORGE_UTILITIES_SOURCES})
