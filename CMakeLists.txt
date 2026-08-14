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

# C++17, not upstream's own C++14 (the Linux CodeLite .project files pass "-std=c++14" explicitly;
# no .vcxproj/.props sets LanguageStandard on Windows, landing on cl.exe's legacy pre-C++17 default).
# 17 is the minimum standard with *guaranteed* copy elision, and that guarantee is load-bearing, not
# cosmetic: Renderer's D3D12MemoryAllocator.h (Graphics/Direct3D12/ThirdParty) has an IUnknownImpl
# with a std::atomic<UINT> member and no user-declared copy constructor, so its implicit copy
# constructor is deleted — real code elsewhere in the same vendored header copy-constructs a derived
# type from a prvalue. Under C++14 (no elision guarantee) that copy is a real, required call to the
# deleted constructor — confirmed directly: clang-cl hard-errors on it ("invokes deleted
# constructor"), even with /WX already off, because this is ill-formed code, not a warning. cl.exe
# tolerates it under C++14 regardless (a real, if silent, divergence — not something this template
# relies on). Under C++17 the same prvalue-copy is guaranteed-elided, so the deleted constructor is
# never actually invoked and the code becomes well-formed on every compiler tried. ForgeSrc is a
# vendored submodule this template never edits, so raising the standard is the only real fix
# available, as opposed to suppressing a diagnostic that was never a warning to begin with.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(WIN32)
    # /EHs-c- /GR- (exceptions/RTTI opt-out, matching TF_Shared.props) can't be set via either
    # cmake/forge-toolchain-clang-cl.cmake's or cmake/forge-toolchain-msvc.cmake's own
    # CMAKE_CXX_FLAGS_INIT — confirmed directly: CMake's own
    # Windows-MSVC.cmake platform module unconditionally appends "/EHsc" to CMAKE_CXX_FLAGS after
    # the toolchain file runs, landing after (and so overriding — cl.exe's D9025 warning, "overriding
    # '/EHs-' with '/EHs'", confirms it) anything set via _INIT. add_compile_options() here, after
    # project(), appends to every target's per-file compile command after CMAKE_CXX_FLAGS, so it
    # wins for real. Also stripped outright below so cl.exe doesn't print a D9025 "overriding" noise
    # warning on literally every C++ file for the rest of this project's life.
    string(REPLACE "/EHsc" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    add_compile_options(
        $<$<COMPILE_LANGUAGE:CXX>:/EHs-c->
        $<$<COMPILE_LANGUAGE:CXX>:/GR->
    )
endif()

# /Z7 instead of /Zi for clang-cl's own Debug builds only (CMAKE_CXX_COMPILER_ID is "Clang" for
# clang-cl, "MSVC" for real cl.exe — the reliable way to tell them apart post-project(), no custom
# variable needed). Same exact "CMAKE_..._INIT gets overridden later" hazard as the /EHsc case just
# above, confirmed directly the same way: cmake/forge-toolchain-clang-cl.cmake's own
# CMAKE_CXX_FLAGS_DEBUG_INIT sets "/Z7 ...", but CMake's own Windows-Clang.cmake platform module still
# force-appends its own default "/Zi ..." afterward regardless — inspecting the real generated
# build.ninja showed both "/Z7 ... /Zi ..." on the same FLAGS line, /Zi landing last and so winning.
# add_compile_options() here lands after CMAKE_CXX_FLAGS for real, same as the /EHsc fix. Real,
# not cosmetic: clang-cl's own PDB writer records each TU's literal (un-collapsed) "../../.."
# vendored include-chain path rather than canonicalizing it the way cl.exe's preprocessor does, and
# that literal string can exceed Windows' legacy MAX_PATH (260 chars) purely from its own length even
# when the real resolved path is short — confirmed via a real CI failure ("path too long", clang-cl's
# own terse diagnostic) that never reproduced locally, where paths are shorter. /Z7 embeds debug info
# per-object instead of accumulating it into one shared .pdb, sidestepping the path-recording step
# that triggers this entirely. cl.exe keeps /Zi (upstream's own real, verified-clean policy, and it
# doesn't have this hazard) — this block intentionally does not touch the msvc toolchain at all.
if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    add_compile_options(
        $<$<AND:$<COMPILE_LANGUAGE:CXX>,$<CONFIG:Debug>>:/Z7>
        $<$<AND:$<COMPILE_LANGUAGE:C>,$<CONFIG:Debug>>:/Z7>
    )
endif()

# Every module's CMakeLists.txt globs its sources from here rather than each hardcoding its own
# relative "../ForgeSrc/Common_3" — one place to repoint if the vendored checkout ever moves.
set(FORGE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/ForgeSrc/Common_3")

# Modules are added here as each one's CMakeLists.txt lands — see plan/module-split.md's build
# order (Utilities -> OS -> Application/Renderer -> AssetPipeline -> Examples).
add_subdirectory(Utilities)
add_subdirectory(OS)
add_subdirectory(Renderer)

if(WIN32)
    # cmake/forge-runtime.cmake applies target_link_libraries()/target_link_options() directly to the
    # real Renderer target, so it's included right after add_subdirectory(Renderer) creates it — not
    # any earlier — but still before any example's own add_subdirectory() (a sibling scope) needs to
    # call its forge_copy_runtime_dlls()/forge_copy_gpu_data() functions. A plain include() runs in
    # the *including* (root) scope, not a new child one the way add_subdirectory() does, so those
    # functions are already present in every later add_subdirectory() scope via normal
    # parent-to-child inheritance. Windows-only, unlike forge-shaders.cmake below — D3D12 vendor-
    # extension linking/DLL copying has no Linux/Vulkan equivalent need here.
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/forge-runtime.cmake")
endif()

# cmake/forge-shaders.cmake compiles Application's own shared FSL shader lists (Screenshot/UI/Fonts —
# every real app's Init() needs these, not just this template's own per-example shaders) exactly
# once, and defines forge_copy_shared_app_shaders() for each example to pull a copy from. Both
# platforms (DIRECT3D12 on Windows, VULKAN on Linux — branched inside that one file, not split into
# per-backend files, matching this project's own if(WIN32)/if(UNIX)-in-one-target convention) — unlike
# forge-runtime.cmake above, doesn't need Renderer to exist first either.
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/forge-shaders.cmake")

add_subdirectory(Application)
add_subdirectory(Scripting)
add_subdirectory(AssetPipeline)
add_subdirectory(Examples/01_Transformations)
