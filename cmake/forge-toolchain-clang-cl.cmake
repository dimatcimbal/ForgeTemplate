# Windows toolchain discovery for ForgeTemplate — clang-cl only.
#
# One of two standalone toolchain files (see forge-toolchain-msvc.cmake for the other) rather than a
# single file with an if(FORGE_TOOLSET_COMPILER STREQUAL "clang-cl")/elseif("msvc") branch selected by
# an extra cache variable. That single-file version needed real, non-obvious machinery purely to make
# the branch work: FORGE_TOOLSET_COMPILER had to be propagated into CMake's own nested try_compile via
# CMAKE_TRY_COMPILE_PLATFORM_VARIABLES (otherwise the branch silently never fired there), plus a
# bespoke pre-project() guard in root CMakeLists.txt to catch a bare `cmake -S . -B build` that forgot
# to set it. Two files selected directly by CMakePresets.json's own CMAKE_TOOLCHAIN_FILE (one per
# compiler family) remove all of that — nothing is parametrized, so nothing needs propagating, and
# root CMakeLists.txt's own guard can check CMAKE_TOOLCHAIN_FILE itself instead of a custom variable.
# The real cost is duplicating the toolset-discovery block below into both files rather than sharing
# it — a deliberate trade, matching this repo's own preference for straightforward, independently-
# readable files over indirection (see build-agent.md); ~20 lines of plain, linear file(GLOB)/
# list(SORT) logic repeated once is cheap next to removing an entire cache-variable-driven mechanism.
#
# Common_3/Application/Config.h whitelists exactly one MSVC toolset (14.29.x, VS2019 16.11,
# _MSC_VER 1929 — confirmed directly in this checkout, Config.h:242), needed here too since clang-cl
# still compiles against real MSVC headers/libs via -vctoolsdir. This script locates whichever
# 14.29.x toolset is actually installed on the current machine, rather than assuming a fixed path, so
# the same preset works across dev machines and CI.

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
# TF_Shared.props' real policy (ExceptionHandling=false, RuntimeTypeInfo=false,
# WarningLevel=Level4, TreatWarningAsError=true, DisableSpecificWarnings=4201;4324;4127) was
# authored and only ever verified against real cl.exe, upstream's sole supported Windows
# toolchain — clang-cl is this template's own addition, and its /W-anything maps to a materially
# broader, differently-shaped Clang diagnostic set than MSVC's own on this ~decade-old vendored
# C/C++ codebase (confirmed directly, on OS alone: -Wsign-compare/-Wmissing-braces/-Wmissing-
# field-initializers/-Wunused-function/-Wformat/-Wnontrivial-memcall/-Wtautological-constant-out-
# of-range-compare/-Wunused-variable/-Wvarargs/-Wignored-qualifiers/-Wdeprecated-copy-with-user-
# provided-copy/-Wdeprecated-declarations/-Wincompatible-pointer-types all fired as -Werror across
# completely unmodified bstrlib/hidapi/imgui/cpu_features/ModifiedSonyMath/Windows*.cpp — none of
# which cl.exe's /W4 raises at all, and every module past this one pulls in more vendored code the
# same way). ForgeSrc is a vendored submodule this template never edits, so there is no fix to
# apply at the source for any of it — only a build-policy choice. clang-cl therefore keeps /W4 for
# visibility but drops /WX: warnings still show up (useful for code written on top of Forge, not
# vendored into it), they just don't fail the build. cl.exe (see forge-toolchain-msvc.cmake) keeps
# full /W4 /WX as upstream's real, verified-clean policy — see Utilities/OS's own build history,
# zero suppressions needed there.
set(_forge_warning_policy "/W4 /wd4201 /wd4324 /wd4127 -Wno-ignored-qualifiers")
# -Wno-ignored-qualifiers — deliberately suppressed outright, unlike every other clang-cl-only
# diagnostic this file already leaves visible (see the bullet list above: -Wsign-compare/
# -Wmissing-braces/-Wdeprecated-copy-with-user-provided-copy/etc. all still fire, on purpose, since
# /WX is already dropped and this repo's own stated goal is still seeing them). This one is a real,
# measured exception, not a blanket "quiet things down" reflex: a real CI build's own warning log was
# pulled and categorized directly (`grep -oP '\[-W[a-zA-Z0-9-]+\]' | sort | uniq -c`), and
# -Wignored-qualifiers alone accounted for 13,820 of ~16,800 total warnings (82%) — and *every single
# one*, confirmed by extracting the actual message text, is the identical, purely cosmetic "'const'
# type qualifier on return type has no effect" (returning `const T` by value, where the `const` is
# genuinely meaningless in C++ since the return is a temporary copy regardless — a pervasive Forge-
# own coding-style choice, not a bug, and not something clang-cl's real C mode error class from
# -Wincompatible-pointer-types above is). Zero incremental diagnostic value past the first instance,
# and its sheer volume actively buried every other, more varied warning category (the 2nd-largest,
# -Wdeprecated-copy-with-user-provided-copy at 1,882 instances, is a real — if likely benign for these
# specific small SIMD-vector-wrapper types — Rule-of-Three pattern across ModifiedSonyMath's own
# Vector3/Vector4/Quat/etc. and ozz-animation's own span<T>, and deliberately left fully visible
# here, not swept into this same suppression, since it's genuine repeated signal, not pure noise like
# -Wignored-qualifiers is). Confirmed directly there's no real "lower the severity but still show it"
# middle ground for a named clang diagnostic group via any command-line flag (checked clang-cl's own
# full `-help`/`-help-hidden` output) — the only way to change a diagnostic's severity rather than its
# plain on/off state is a `#pragma clang diagnostic` block in the source itself, which would mean
# editing ForgeSrc. -Wno- (a real, native clang flag, not an MSVC-style /wd numeric code — clang-cl
# accepts both styles mixed on the same command line, already proven by -Wno-incompatible-pointer-
# types below) is in the shared policy variable, not scoped to C only like that one is, since this
# diagnostic fires across both C and C++ vendored files alike (confirmed in the same log pull).
# -Wincompatible-pointer-types (Direct3D12.c/Direct3D12Raytracing.c/Direct3D12Hooks.c's COM
# QueryInterface calls, T** passed where the vtbl expects void**) is NOT gated by /WX at all —
# confirmed directly: it still fires as "error:" with /WX already dropped above, because clang-cl's
# C mode makes this class of diagnostic a hard error unconditionally. -Wno- (not -Wno-error=) is
# the only way to actually silence it.
set(CMAKE_C_FLAGS_INIT "${_forge_vctools_flag} ${_forge_warning_policy} /D_HAS_EXCEPTIONS=0 -Wno-incompatible-pointer-types")
set(CMAKE_CXX_FLAGS_INIT "${_forge_vctools_flag} ${_forge_warning_policy} /D_HAS_EXCEPTIONS=0")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-vctoolsdir \"${FORGE_MSVC_TOOLSET_DIR}\"")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-vctoolsdir \"${FORGE_MSVC_TOOLSET_DIR}\"")

# /Z7 instead of CMake's own MSVC-frontend default /Zi for Debug — real, confirmed-directly-on-CI
# clang-cl-specific hazard (never reproduced locally, where paths are shorter): clang-cl's own PDB
# writer needs to record every translation unit's absolute source path, and unlike cl.exe's own
# preprocessor it doesn't collapse Forge's own vendored deep "../../.." relative #include chains
# before recording them, so the literal (un-collapsed) recorded path can exceed Windows' legacy
# MAX_PATH (260 chars) even when the real, resolved path is well under it — confirmed via a real CI
# failure ("path too long", clang-cl's own terse diagnostic, no further detail given) on 3 separate
# vendored files, GitHub Actions' own longer runner workspace path (D:\a\<repo>\<repo>\...) plus a
# longer discovered toolset directory name (VS2022 Enterprise vs. this dev machine's own Community)
# apparently enough to tip already-borderline-long recorded paths over the limit. /Z7 embeds debug
# info directly per-object instead of accumulating it into one shared .pdb, sidestepping the shared-
# PDB path-recording step entirely — a real, standard mitigation for exactly this class of clang-cl-
# on-Windows issue, not specific to this vendored codebase. Paired with a shortened CI checkout path
# (see .github/workflows/pr_to_main.yml) as a second, independent mitigation for the same root cause.
set(CMAKE_C_FLAGS_DEBUG_INIT "/Z7 /Ob0 /Od /RTC1")
set(CMAKE_CXX_FLAGS_DEBUG_INIT "/Z7 /Ob0 /Od /RTC1")
