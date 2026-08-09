# Common_3/Application — ImGui-based UI (UI.cpp/imgui_user.cpp + vendored ThirdParty/OpenSource/
# imgui), FontSystem, the GPU profiler overlay, and CameraController. Platform-neutral source itself
# (no if(WIN32)/if(UNIX) split needed here) — everything platform-specific is already isolated one
# layer down, inside OS.
#
# Depends on Utilities+OS+Renderer, listed explicitly rather than relying on Renderer's own PUBLIC
# chain to pull Utilities/OS in transitively — real, direct dependencies of this module's own source,
# confirmed directly: UI.cpp calls LOGF/etc. (Utilities), inputGetValue (OS), and
# addPipeline/addShader/cmdBindPipeline; GpuProfiler.cpp calls getTimestampFrequency (both Renderer)
# — not just unused header includes (contrast Resources/ResourceLoader/ResourceLoader.cpp's
# Application/Game includes, which really are unused). PUBLIC, not PRIVATE — Application is a static
# library, so these are usage requirements that propagate to whatever executable eventually links it,
# same reasoning as OS's own GTK/X11 link libraries.
#
# Every header here is reached via paths relative to the including file itself, same pattern as every
# other module so far — no target_include_directories needed.

file(GLOB FORGE_APPLICATION_SOURCES
    "${FORGE_ROOT}/Application/UI/*.cpp"
    "${FORGE_ROOT}/Application/Fonts/*.cpp"
    "${FORGE_ROOT}/Application/Profiler/*.cpp"
    "${FORGE_ROOT}/Application/Screenshot/*.cpp"
    "${FORGE_ROOT}/Application/ThirdParty/OpenSource/imgui/*.cpp"
)
# Non-recursive glob, deliberately — Application/*.cpp is CameraController.cpp alone (confirmed);
# Application/ itself also holds the excluded IApp/Application framework layer in subdirectories this
# template doesn't build, which a recursive glob would sweep in.
file(GLOB FORGE_APPLICATION_TOP_LEVEL_SOURCES "${FORGE_ROOT}/Application/*.cpp")
list(APPEND FORGE_APPLICATION_SOURCES ${FORGE_APPLICATION_TOP_LEVEL_SOURCES})

add_library(Application STATIC ${FORGE_APPLICATION_SOURCES})
target_link_libraries(Application PUBLIC Utilities OS Renderer)

if(UNIX)
    # Fonts/stbtt.cpp includes Utilities/Interfaces/IMemory.h (which #defines `delete` to force
    # tf_free instead — the known Forge pitfall of needing IMemory.h to be a TU's last include) BEFORE
    # its own #include of stb_truetype.h. On Windows this is harmless; on Linux, stb_truetype.h's own
    # "#include <math.h>" transitively pulls libstdc++'s <cmath> -> bits/specfun.h ->
    # bits/stl_iterator_base_funcs.h, which has real "= delete"d iterator-helper overloads that then
    # get corrupted into "= static_assert(false, ...)" — a hard syntax error, confirmed identically
    # under both GCC and Clang (both use libstdc++ here). Can't reorder vendored stbtt.cpp's own
    # includes, so force <cmath> in ahead of the whole translation unit instead: its include guard
    # then makes stb_truetype.h's later "#include <math.h>" a no-op, so IMemory.h's macro never
    # actually reaches those STL declarations.
    target_compile_options(Application PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-include cmath>)

    # A recurring Forge bug on Linux, not a one-off: several Application/* .cpp files #include their
    # own FSL-generated header with different case than the real vendored file on disk — silently
    # fine on Windows/macOS's case-insensitive filesystems, a hard "No such file or directory" on
    # Linux's case-sensitive one, each one only ever caught via a real CI build (not a scan). Rather
    # than writing a case-variant file into ForgeSrc's own working tree (a vendored submodule this
    # template never touches, not even with an untracked file), every mismatch gets a one-line
    # forwarding header generated entirely inside our own build directory (already gitignored),
    # findable via a single shared -iquote directory below — the compiler's own quote-include lookup
    # already checks the including file's directory first (misses, case mismatch) before falling
    # through to -iquote directories, so each shim only ever activates exactly when the real lookup
    # fails. Each shim's own path under this directory must mirror how its *including* file wrote
    # the #include (with or without a "Shaders/FSL/" prefix), not the real file's actual location.
    set(FORGE_APPLICATION_FSL_SHIM_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated-includes")

    # Fonts/FontSystem.cpp: #include "./Shaders/FSL/Resources.h" vs. real "resources.h".
    if(NOT EXISTS "${FORGE_APPLICATION_FSL_SHIM_DIR}/Shaders/FSL/Resources.h")
        file(WRITE "${FORGE_APPLICATION_FSL_SHIM_DIR}/Shaders/FSL/Resources.h"
            "#include \"${FORGE_ROOT}/Application/Fonts/Shaders/FSL/resources.h\"\n")
    endif()

    # resources.h itself (just forwarded to above): #include "FontStash.srt.h" vs. real
    # "fontstash.srt.h" — a bare filename this time (no subdirectory prefix), so it lands at the top
    # of the shim dir rather than nested under Shaders/FSL/.
    if(NOT EXISTS "${FORGE_APPLICATION_FSL_SHIM_DIR}/FontStash.srt.h")
        file(WRITE "${FORGE_APPLICATION_FSL_SHIM_DIR}/FontStash.srt.h"
            "#include \"${FORGE_ROOT}/Application/Fonts/Shaders/FSL/fontstash.srt.h\"\n")
    endif()

    # Screenshot/Screenshot.cpp: #include "./Shaders/FSL/Copy.comp.srt.h" vs. real
    # "copy.comp.srt.h" — same "Shaders/FSL/" prefix shape as Resources.h above, but resolving to a
    # different real file in a different Application/* subdirectory (Screenshot, not Fonts).
    if(NOT EXISTS "${FORGE_APPLICATION_FSL_SHIM_DIR}/Shaders/FSL/Copy.comp.srt.h")
        file(WRITE "${FORGE_APPLICATION_FSL_SHIM_DIR}/Shaders/FSL/Copy.comp.srt.h"
            "#include \"${FORGE_ROOT}/Application/Screenshot/Shaders/FSL/copy.comp.srt.h\"\n")
    endif()

    target_compile_options(Application PRIVATE -iquote "${FORGE_APPLICATION_FSL_SHIM_DIR}")
endif()
