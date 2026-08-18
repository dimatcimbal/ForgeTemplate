# Common_3/Graphics + Resources/ResourceLoader + Tools/Network + Tools/ReloadServer — the graphics
# backend (D3D12 on Windows, Vulkan on Linux — exactly one per platform, never both fused into one
# binary), plus the platform-neutral resource-loading/live-shader-reload machinery built on top of it.
#
# DIRECT3D12/VULKAN aren't defined here — GraphicsConfig.h self-selects the backend from _WINDOWS/
# __linux__ automatically; don't add them as target_compile_definitions.

if(WIN32)
    file(GLOB FORGE_RENDERER_SOURCES
        "${FORGE_ROOT}/Graphics/Direct3D12/*.c"
        "${FORGE_ROOT}/Graphics/Direct3D12/*.cpp"
    )
    # Direct3D12Hooks.c (kept) and Direct3D12Hooks.cpp (excluded) are two separate files sharing a
    # base name — upstream's own Renderer.vcxproj compiles the .c, not the .cpp.
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

# D3D12 vendor-extension import libs, the /FORCE:MULTIPLE linker workaround, and runtime DLL/
# gpu.data copying all live in cmake/forge-runtime.cmake instead — applied to this exact target from
# root CMakeLists.txt right after add_subdirectory(Renderer) creates it.
