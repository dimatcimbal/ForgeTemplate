# Windows toolchain discovery for ForgeTemplate — clang-cl only.
#
# One of two standalone toolchain files (see forge-toolchain-msvc.cmake for the other) rather than a
# single file with an if(FORGE_TOOLSET_COMPILER STREQUAL "clang-cl")/elseif("msvc") branch selected by
# an extra cache variable — that shape needed FORGE_TOOLSET_COMPILER propagated into CMake's own
# nested try_compile via CMAKE_TRY_COMPILE_PLATFORM_VARIABLES (the branch otherwise silently never
# fires there), plus a pre-project() guard in root CMakeLists.txt to catch a bare
# `cmake -S . -B build` that forgot to set it. Don't merge these two files back into one branched
# file — the toolset-discovery block duplicated below is the accepted cost of avoiding that machinery.
#
# Common_3/Application/Config.h whitelists exactly one MSVC toolset (14.29.x, VS2019 16.11,
# _MSC_VER 1929), needed here too since clang-cl still compiles against real MSVC headers/libs via
# -vctoolsdir. This script locates whichever 14.29.x toolset is actually installed on the current
# machine, rather than assuming a fixed path, so the same preset works across dev machines and CI.

file(TO_CMAKE_PATH "$ENV{ProgramFiles}" _forge_program_files)
file(TO_CMAKE_PATH "$ENV{ProgramFiles\(x86\)}" _forge_program_files_x86)

file(GLOB _forge_toolset_dirs
    "${_forge_program_files}/Microsoft Visual Studio/*/*/VC/Tools/MSVC/14.29.*"
    "${_forge_program_files_x86}/Microsoft Visual Studio/*/*/VC/Tools/MSVC/14.29.*"
)
if(NOT _forge_toolset_dirs)
    message(FATAL_ERROR
        "No VS2019 16.11 (MSVC 14.29.x / _MSC_VER 1929) toolset found. Common_3/Application/Config.h "
        "whitelists this exact toolset. Install 'MSVC v142 - VS 2019 C++ x64/x86 build tools "
        "(14.29-16.11)' via the Visual Studio Installer.")
endif()
list(SORT _forge_toolset_dirs)
list(GET _forge_toolset_dirs -1 FORGE_MSVC_TOOLSET_DIR)

message(STATUS "Forge toolset: ${FORGE_MSVC_TOOLSET_DIR}")

set(CMAKE_C_COMPILER clang-cl CACHE STRING "")
set(CMAKE_CXX_COMPILER clang-cl CACHE STRING "")

set(_forge_vctools_flag "-fms-compatibility-version=19.29 -vctoolsdir \"${FORGE_MSVC_TOOLSET_DIR}\"")
# TF_Shared.props' real policy (WarningLevel=Level4, TreatWarningAsError=true) was authored and only
# ever verified against real cl.exe — clang-cl's /W-anything maps to a materially broader,
# differently-shaped Clang diagnostic set on this ~decade-old vendored codebase, firing as -Werror on
# entirely unmodified vendored files that cl.exe's /W4 doesn't raise at all. ForgeSrc is never edited,
# so there's no source-side fix — clang-cl keeps /W4 for visibility but drops /WX: warnings still
# show up, they just don't fail the build. cl.exe (see forge-toolchain-msvc.cmake) keeps full
# /W4 /WX as upstream's real, verified-clean policy.
set(_forge_warning_policy "/W4 /wd4201 /wd4324 /wd4127 -Wno-ignored-qualifiers")
# -Wno-ignored-qualifiers — deliberately suppressed outright, unlike every other clang-cl-only
# diagnostic here (those stay visible, /WX is already dropped). A measured exception, not a blanket
# "quiet things down" reflex: this single diagnostic accounted for 82% of all clang-cl warnings on
# this codebase, and every instance is the identical, purely cosmetic "'const' type qualifier on
# return type has no effect" — zero incremental diagnostic value, and its volume buried every other,
# more varied warning category. There's no "lower the severity but still show it" middle ground for a
# named clang diagnostic group via any command-line flag — the only way to change severity rather
# than plain on/off is a `#pragma clang diagnostic` block in the source, which would mean editing
# ForgeSrc.
# -Wincompatible-pointer-types (Direct3D12.c's COM QueryInterface calls, T** passed where the vtbl
# expects void**) is NOT gated by /WX at all — clang-cl's C mode makes this class of diagnostic a
# hard error unconditionally. -Wno- (not -Wno-error=) is the only way to silence it.
set(CMAKE_C_FLAGS_INIT "${_forge_vctools_flag} ${_forge_warning_policy} /D_HAS_EXCEPTIONS=0 -Wno-incompatible-pointer-types")
set(CMAKE_CXX_FLAGS_INIT "${_forge_vctools_flag} ${_forge_warning_policy} /D_HAS_EXCEPTIONS=0")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-vctoolsdir \"${FORGE_MSVC_TOOLSET_DIR}\"")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-vctoolsdir \"${FORGE_MSVC_TOOLSET_DIR}\"")

# /Z7 instead of CMake's own MSVC-frontend default /Zi for Debug — clang-cl's own PDB writer records
# every translation unit's un-collapsed "../../.." vendored include-chain path rather than
# canonicalizing it, which can exceed Windows' 260-char MAX_PATH purely from its own length. /Z7
# embeds debug info per-object instead of one shared .pdb, avoiding that path-recording step. Paired
# with a shortened CI checkout path (see .github/workflows/pr_to_main.yml) as a second, independent
# mitigation for the same root cause.
set(CMAKE_C_FLAGS_DEBUG_INIT "/Z7 /Ob0 /Od /RTC1")
set(CMAKE_CXX_FLAGS_DEBUG_INIT "/Z7 /Ob0 /Od /RTC1")
