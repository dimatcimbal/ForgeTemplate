# Common_3/Graphics + Resources/ResourceLoader + Tools/Network + Tools/ReloadServer — the graphics
# backend (D3D12 on Windows, Vulkan on Linux — exactly one per platform, never both fused into one
# binary, matching the real, confirmed upstream pattern: PC_VS2019/Libraries/Renderer/Renderer.vcxproj
# is D3D12-only, Android_VS2019's copy of the same project is Vulkan-only), plus the
# platform-neutral resource-loading/live-shader-reload machinery built on top of it.
#
# DIRECT3D12/VULKAN aren't defined here — GraphicsConfig.h self-selects the backend from _WINDOWS/
# __linux__ (both already defined by the compiler/CMake defaults) and each backend's own ConfigConfig.h
# #defines its own macro, confirmed directly. Same for Direct3D12's Agility SDK d3d12.h and Vulkan's
# vendored SDK headers — both reached via paths relative to the including file (Direct3D12Config.h:54,
# VulkanConfig.h:53), fully vendored in ForgeSrc, no target_include_directories needed here either.

if(WIN32)
    file(GLOB FORGE_RENDERER_SOURCES
        "${FORGE_ROOT}/Graphics/Direct3D12/*.c"
        "${FORGE_ROOT}/Graphics/Direct3D12/*.cpp"
    )
    # Direct3D12Hooks.c (kept) and Direct3D12Hooks.cpp (excluded) are two separate files sharing a
    # base name — only the .cpp one is upstream's own exclusion (confirmed: PC_VS2019's real
    # Renderer.vcxproj compiles the .c, not the .cpp).
    list(FILTER FORGE_RENDERER_SOURCES EXCLUDE REGEX "Direct3D12Hooks\\.cpp$")
elseif(UNIX)
    file(GLOB FORGE_RENDERER_SOURCES
        "${FORGE_ROOT}/Graphics/Vulkan/*.c"
        "${FORGE_ROOT}/Graphics/Vulkan/*.cpp"
    )
endif()

list(APPEND FORGE_RENDERER_SOURCES
    "${FORGE_ROOT}/Graphics/GraphicsConfig.cpp"
    "${FORGE_ROOT}/Resources/ResourceLoader/ResourceLoader.cpp"
    "${FORGE_ROOT}/Tools/Network/Network.c"
    "${FORGE_ROOT}/Tools/ReloadServer/ReloadClient.cpp"
)

add_library(Renderer STATIC ${FORGE_RENDERER_SOURCES})
target_link_libraries(Renderer PUBLIC Utilities OS)

# D3D12 vendor-extension import libs (dxcompiler/AGS/NVAPI/WinPixEventRuntime/xinput), the
# /FORCE:MULTIPLE linker workaround, and runtime DLL / gpu.data copying for whatever executable
# actually links Renderer all live in cmake/forge-runtime.cmake instead, applied to this exact
# target from the root CMakeLists.txt right after add_subdirectory(Renderer) creates it — Forge's
# D3D12 runtime environment is a separate concern every example needs equally, not particular to
# what source files build the Renderer library itself.
