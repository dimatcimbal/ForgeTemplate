# Windows toolchain discovery for ForgeTemplate.
#
# Common_3/Application/Config.h whitelists exactly one MSVC toolset (14.29.x, VS2019 16.11,
# _MSC_VER 1929 — confirmed directly in this checkout, Config.h:242). This script locates
# whichever 14.29.x toolset and Windows SDK are actually installed on the current machine,
# rather than assuming a fixed path, so the same presets work across dev machines and CI.
# Confirmed necessary, not just theoretical: a real MSBuild build of ForgeSrc's own
# Examples_3/Unit_Tests/PC_VS2019/Unit_Tests.sln on this exact machine failed with
# "MSB8036: The Windows SDK version 10.0.17763.0 was not found" — every real .vcxproj hardcodes
# that one SDK version, which isn't installed here (only 10.0.22621.0/10.0.26100.0 are).
#
# FORGE_TOOLSET_COMPILER selects which compiler front-end to pin: "clang-cl" or "msvc".
#
# No vcpkg involved — unlike a manifest-driven vcpkg project, every third-party dependency this
# template curates (bstrlib/lz4/zstd/imgui/ozz-animation/ispc_texcomp/BunyLib/meshoptimizer/cgltf/
# tinyimageformat/tinydds/tinyktx) is vendored directly in ForgeSrc, and the Vulkan SDK is found
# via its own VULKAN_SDK environment variable, not a package manager. So this file is set directly
# as CMAKE_TOOLCHAIN_FILE in CMakePresets.json, not chainloaded through vcpkg's own toolchain file.

# CMake's ABI-detection step runs in an isolated nested try_compile that re-processes this
# toolchain file fresh — without this, FORGE_TOOLSET_COMPILER isn't visible there, the branch
# below never fires, and the nested sub-configure ends up with no compiler set at all.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
    FORGE_TOOLSET_COMPILER
)

# Normalized once, at the source, rather than composed piecemeal later — $ENV{...} returns
# Windows-native backslash paths, and composing a few segments with TO_CMAKE_PATH while leaving
# others as raw $ENV{...} references produces paths with mixed separators (e.g. "C:\Program
# Files/Microsoft...", missing the slash after "C:" entirely in one observed case).
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

file(GLOB _forge_sdk_include_dirs "${_forge_program_files_x86}/Windows Kits/10/Include/10.0.*")
if(NOT _forge_sdk_include_dirs)
    message(FATAL_ERROR "No Windows 10/11 SDK found under 'Windows Kits/10/Include'.")
endif()
list(SORT _forge_sdk_include_dirs)
list(GET _forge_sdk_include_dirs -1 _forge_sdk_include_dir)
get_filename_component(FORGE_WINSDK_VERSION "${_forge_sdk_include_dir}" NAME)
set(FORGE_WINSDK_ROOT "${_forge_program_files_x86}/Windows Kits/10")

message(STATUS "Forge toolset: ${FORGE_MSVC_TOOLSET_DIR}")
message(STATUS "Forge Windows SDK: ${FORGE_WINSDK_VERSION}")

if(FORGE_TOOLSET_COMPILER STREQUAL "clang-cl")
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
    # vendored into it), they just don't fail the build. cl.exe keeps full /W4 /WX as upstream's real,
    # verified-clean policy — see Utilities/OS's own build history, zero suppressions needed there.
    set(_forge_warning_policy "/W4 /wd4201 /wd4324 /wd4127")
    # -Wincompatible-pointer-types (Direct3D12.c/Direct3D12Raytracing.c/Direct3D12Hooks.c's COM
    # QueryInterface calls, T** passed where the vtbl expects void**) is NOT gated by /WX at all —
    # confirmed directly: it still fires as "error:" with /WX already dropped above, because clang-cl's
    # C mode makes this class of diagnostic a hard error unconditionally. -Wno- (not -Wno-error=) is
    # the only way to actually silence it.
    set(CMAKE_C_FLAGS_INIT "${_forge_vctools_flag} ${_forge_warning_policy} /D_HAS_EXCEPTIONS=0 -Wno-incompatible-pointer-types")
    set(CMAKE_CXX_FLAGS_INIT "${_forge_vctools_flag} ${_forge_warning_policy} /D_HAS_EXCEPTIONS=0")
    set(CMAKE_EXE_LINKER_FLAGS_INIT "-vctoolsdir \"${FORGE_MSVC_TOOLSET_DIR}\"")
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "-vctoolsdir \"${FORGE_MSVC_TOOLSET_DIR}\"")
elseif(FORGE_TOOLSET_COMPILER STREQUAL "msvc")
    set(CMAKE_C_COMPILER "${FORGE_MSVC_TOOLSET_DIR}/bin/Hostx64/x64/cl.exe" CACHE STRING "")
    set(CMAKE_CXX_COMPILER "${FORGE_MSVC_TOOLSET_DIR}/bin/Hostx64/x64/cl.exe" CACHE STRING "")
    set(CMAKE_RC_COMPILER "${FORGE_WINSDK_ROOT}/bin/${FORGE_WINSDK_VERSION}/x64/rc.exe" CACHE STRING "")
    set(CMAKE_MT "${FORGE_WINSDK_ROOT}/bin/${FORGE_WINSDK_VERSION}/x64/mt.exe" CACHE STRING "")

    # /I and /LIBPATH: flags, not INCLUDE/LIB env vars — env vars set here only affect this
    # configure-time cmake.exe process, not the separate ninja process a later `cmake --build`
    # spawns, so they'd silently vanish by the time anything actually compiles.
    set(_forge_msvc_include_flags
        "/I\"${FORGE_MSVC_TOOLSET_DIR}/include\" /I\"${FORGE_WINSDK_ROOT}/Include/${FORGE_WINSDK_VERSION}/ucrt\" /I\"${FORGE_WINSDK_ROOT}/Include/${FORGE_WINSDK_VERSION}/shared\" /I\"${FORGE_WINSDK_ROOT}/Include/${FORGE_WINSDK_VERSION}/um\" /I\"${FORGE_WINSDK_ROOT}/Include/${FORGE_WINSDK_VERSION}/winrt\"")
    # Full TF_Shared.props policy, /WX included — this is upstream's real, verified-clean toolchain
    # (see the clang-cl branch's comment above for why clang-cl doesn't get the same /WX treatment).
    # _CRT_SECURE_NO_WARNINGS is defined for symmetry with the clang-cl branch even though cl.exe
    # doesn't need it (it doesn't warn on CRT "insecure function" use on this vendored source at all).
    set(_forge_warning_policy "/W4 /WX /wd4201 /wd4324 /wd4127")
    set(_forge_preprocessor_defs "/D_HAS_EXCEPTIONS=0 /D_CRT_SECURE_NO_WARNINGS")
    set(CMAKE_C_FLAGS_INIT "${_forge_msvc_include_flags} ${_forge_warning_policy} ${_forge_preprocessor_defs}")
    # /permissive- confirmed against this project's own Utilities+OS module builds, both compiling
    # clean under real cl.exe with strict conformance mode. /EHs-c- /GR- (exceptions/RTTI opt-out) are
    # NOT set here — see the root CMakeLists.txt's add_compile_options() call for why.
    set(CMAKE_CXX_FLAGS_INIT "${_forge_msvc_include_flags} ${_forge_warning_policy} ${_forge_preprocessor_defs} /permissive-")

    set(_forge_msvc_libpath_flags
        "/LIBPATH:\"${FORGE_MSVC_TOOLSET_DIR}/lib/x64\" /LIBPATH:\"${FORGE_WINSDK_ROOT}/Lib/${FORGE_WINSDK_VERSION}/ucrt/x64\" /LIBPATH:\"${FORGE_WINSDK_ROOT}/Lib/${FORGE_WINSDK_VERSION}/um/x64\"")
    set(CMAKE_EXE_LINKER_FLAGS_INIT "${_forge_msvc_libpath_flags}")
    set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_forge_msvc_libpath_flags}")
else()
    message(FATAL_ERROR "FORGE_TOOLSET_COMPILER must be set to \"clang-cl\" or \"msvc\" (got: \"${FORGE_TOOLSET_COMPILER}\")")
endif()
