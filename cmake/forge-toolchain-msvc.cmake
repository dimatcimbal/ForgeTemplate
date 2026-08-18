# Windows toolchain discovery for ForgeTemplate — real cl.exe only.
#
# One of two standalone toolchain files (see forge-toolchain-clang-cl.cmake for the other and its own
# header comment for why this is two files rather than one with a branch). Real, not just
# theoretical: a plain MSBuild build of ForgeSrc's own Unit_Tests.sln on this exact machine failed
# with "MSB8036: The Windows SDK version 10.0.17763.0 was not found" — every real .vcxproj hardcodes
# that one SDK version, which isn't installed here — hence discovering whatever's actually present
# rather than assuming a fixed version.
#
# No vcpkg involved — every third-party dependency this template curates is vendored directly in
# ForgeSrc, and the Vulkan SDK is found via its own VULKAN_SDK environment variable. This file is set
# directly as CMAKE_TOOLCHAIN_FILE in CMakePresets.json, not chainloaded through vcpkg's own.

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

set(CMAKE_C_COMPILER "${FORGE_MSVC_TOOLSET_DIR}/bin/Hostx64/x64/cl.exe" CACHE STRING "")
set(CMAKE_CXX_COMPILER "${FORGE_MSVC_TOOLSET_DIR}/bin/Hostx64/x64/cl.exe" CACHE STRING "")
set(CMAKE_RC_COMPILER "${FORGE_WINSDK_ROOT}/bin/${FORGE_WINSDK_VERSION}/x64/rc.exe" CACHE STRING "")
set(CMAKE_MT "${FORGE_WINSDK_ROOT}/bin/${FORGE_WINSDK_VERSION}/x64/mt.exe" CACHE STRING "")

# /I and /LIBPATH: flags, not INCLUDE/LIB env vars — env vars set here only affect this
# configure-time cmake.exe process, not the separate ninja process a later `cmake --build`
# spawns, so they'd silently vanish by the time anything actually compiles.
set(_forge_msvc_include_flags
    "/I\"${FORGE_MSVC_TOOLSET_DIR}/include\" /I\"${FORGE_WINSDK_ROOT}/Include/${FORGE_WINSDK_VERSION}/ucrt\" /I\"${FORGE_WINSDK_ROOT}/Include/${FORGE_WINSDK_VERSION}/shared\" /I\"${FORGE_WINSDK_ROOT}/Include/${FORGE_WINSDK_VERSION}/um\" /I\"${FORGE_WINSDK_ROOT}/Include/${FORGE_WINSDK_VERSION}/winrt\"")
# Full TF_Shared.props policy, /WX included — this is upstream's real, verified-clean toolchain (see
# forge-toolchain-clang-cl.cmake's own comment for why clang-cl doesn't get the same /WX treatment).
# _CRT_SECURE_NO_WARNINGS is defined for symmetry with the clang-cl branch even though cl.exe
# doesn't need it (it doesn't warn on CRT "insecure function" use on this vendored source at all).
set(_forge_warning_policy "/W4 /WX /wd4201 /wd4324 /wd4127")
set(_forge_preprocessor_defs "/D_HAS_EXCEPTIONS=0 /D_CRT_SECURE_NO_WARNINGS")
set(CMAKE_C_FLAGS_INIT "${_forge_msvc_include_flags} ${_forge_warning_policy} ${_forge_preprocessor_defs}")
# /permissive- compiles clean under real cl.exe with strict conformance mode on this codebase.
# /EHs-c- /GR- (exceptions/RTTI opt-out) are NOT set here — see root CMakeLists.txt's
# add_compile_options() call for why.
set(CMAKE_CXX_FLAGS_INIT "${_forge_msvc_include_flags} ${_forge_warning_policy} ${_forge_preprocessor_defs} /permissive-")

set(_forge_msvc_libpath_flags
    "/LIBPATH:\"${FORGE_MSVC_TOOLSET_DIR}/lib/x64\" /LIBPATH:\"${FORGE_WINSDK_ROOT}/Lib/${FORGE_WINSDK_VERSION}/ucrt/x64\" /LIBPATH:\"${FORGE_WINSDK_ROOT}/Lib/${FORGE_WINSDK_VERSION}/um/x64\"")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_forge_msvc_libpath_flags}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_forge_msvc_libpath_flags}")
