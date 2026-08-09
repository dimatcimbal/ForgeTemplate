# Everything the D3D12 backend needs beyond compiling Renderer's own source: vendor-extension
# import libs, the linker workaround their vendored commit needs against a modern Windows SDK, and
# the runtime DLLs/gpu.data every executable that links Renderer must carry next to itself. All one
# module rather than living inside Renderer/CMakeLists.txt, which stays scoped to "what source files
# build the Renderer library" — this file is Forge's own D3D12 runtime environment, a separate
# concern every example needs equally, not particular to Renderer's own build.
#
# Included once from the root CMakeLists.txt (Windows only), *after* add_subdirectory(Renderer) so
# the Renderer target already exists when this file applies target_link_libraries()/
# target_link_options() to it directly, but still before any example's own add_subdirectory() (a
# sibling scope) needs to call forge_copy_runtime_dlls()/forge_copy_gpu_data() — a plain include()
# runs in the *including* (root) scope, not a new child one the way add_subdirectory() does, so
# those two functions and FORGE_RUNTIME_DLLS/FORGE_GPU_DATA are already present there via normal
# parent-to-child inheritance.

# dxguid.lib (pulled in transitively via Direct3D12.c's own #pragma comment) and Direct3D12.c itself
# both define IID_ID3D12GraphicsCommandList10/IID_ID3D12StateObjectProperties1/
# IID_ID3D12WorkGraphProperties — a real conflict between this vendored commit and a modern Windows
# SDK's own dxguid.lib (both ship these GUIDs; the older SDK this code was written against didn't
# have them yet), confirmed independently reproducible against a real MSBuild build of ForgeSrc's own
# Unit_Tests.sln, not specific to this template's own CMake wiring. /FORCE:MULTIPLE tells the linker
# to keep one definition and move on rather than erroring; PUBLIC so it applies transitively to any
# final executable link.
target_link_options(Renderer PUBLIC "/FORCE:MULTIPLE")

# xinput (WindowsInput.cpp's gamepad support — not pragma'd anywhere, confirmed directly via a real
# link failure) and three real D3D12 vendor-extension import libs (dxcompiler.lib for runtime shader
# compilation, amd_ags_x64.lib/nvapi64.lib for AMD/NVIDIA driver-info queries) whose corresponding
# DLLs are copied at runtime by forge_copy_runtime_dlls() below — the .lib here is link-time only, a
# separate concern from the runtime .dll. PUBLIC, not PRIVATE — Renderer is a static library, so
# these are usage requirements that only actually get linked into whatever executable eventually
# links Renderer, same reasoning as OS's own GTK/X11 link libraries.
target_link_libraries(Renderer PUBLIC
    xinput
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/DirectXShaderCompiler/lib/x64/dxcompiler.lib"
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/ags/ags_lib/lib/amd_ags_x64.lib"
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/nvapi/amd64/nvapi64.lib"
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/winpixeventruntime/bin/WinPixEventRuntime.lib"
)

# The .lib files linked above are just import libs — the actual DLLs Direct3D12.c/dxcompiler load at
# runtime (dxcompiler/dxil for shader-compiler helpers, WinPixEventRuntime for GPU markers, AGS for
# AMD vendor-extension queries) need to sit next to whichever executable runs, and the Agility SDK
# redistributable (D3D12Core.dll/d3d12SDKLayers.dll) is required by any executable that exports
# D3D12SDKVersion/D3D12SDKPath (Forge's own DEFINE_APPLICATION_MAIN does this) — without it
# D3D12CreateDevice ignores the vendored Agility SDK and rejects real hardware adapters outright.
set(FORGE_RUNTIME_DLLS
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/DirectXShaderCompiler/bin/x64/dxcompiler.dll"
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/DirectXShaderCompiler/bin/x64/dxil.dll"
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/winpixeventruntime/bin/WinPixEventRuntime.dll"
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/ags/ags_lib/lib/amd_ags_x64.dll"
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/Direct3d12Agility/bin/x64/D3D12Core.dll"
    "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/Direct3d12Agility/bin/x64/d3d12SDKLayers.dll"
)

function(forge_copy_runtime_dlls TargetName)
    add_custom_command(TARGET ${TargetName} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${FORGE_RUNTIME_DLLS}
            "$<TARGET_FILE_DIR:${TargetName}>"
    )
endfunction()

# GraphicsConfig.cpp's initGPUConfiguration reads "gpu.data" from RD_OTHER_FILES (a GPU vendor/model
# -> preset-tier database, confirmed directly — NOT RD_GPU_CONFIG, which is a separate, optional
# "gpu.cfg" override file) — a real file Forge vendors at OS/Windows/pc_gpu.data, not something this
# project authors. Left uncopied, initGPUConfiguration silently falls back to the lowest GPU preset
# for every real GPU, harmless but unnecessarily pessimistic. RD_OTHER_FILES is never mapped in any
# PathStatement.txt, so it resolves to an empty mPath (FileSystem.c's gResourceDirectories starts
# zero-initialized), i.e. plain CWD — the same directory forge_copy_runtime_dlls already copies into,
# hence the plain "gpu.data" rename (no subdirectory) rather than something PathStatement.txt-relative.
set(FORGE_GPU_DATA "${FORGE_ROOT}/OS/Windows/pc_gpu.data")

function(forge_copy_gpu_data TargetName)
    add_custom_command(TARGET ${TargetName} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${FORGE_GPU_DATA}"
            "$<TARGET_FILE_DIR:${TargetName}>/gpu.data"
    )
endfunction()
