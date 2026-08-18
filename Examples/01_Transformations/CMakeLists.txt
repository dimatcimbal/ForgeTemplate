# The first real end-to-end example — mirrors Examples_3/Unit_Tests/src/01_Transformations verbatim
# (a single unmodified vendored .cpp). Uses Forge's own IApp/DEFINE_APPLICATION_MAIN/WindowsMain(/
# LinuxMain on Linux) application framework directly.
#
# Builds on both Windows (D3D12) and Linux (Vulkan), matching upstream's own real SteamOS_CodeLite/
# 01_Transformations.project. Every FSL invocation/link/runtime-asset step below branches per
# platform for that reason — don't assume Windows-only when editing this file.

# Every module 01_Transformations.cpp's own code actually calls into, listed explicitly:
#   - Utilities: ILog/IFileSystem calls
#   - OS: WindowsMain/LinuxMain (DEFINE_APPLICATION_MAIN's per-platform entry point)
#   - Renderer: IGraphics calls (addPipeline/addShader/cmdBindPipeline/...)
#   - Application: IUI/IProfiler/IScreenshot calls (initUserInterface/initProfiler/...)
#   - Scripting: WindowsMain/LinuxMain unconditionally calls into Lua scripting hooks, not something
#     01_Transformations.cpp calls itself

set(FORGE_EXAMPLE_SRC "${FORGE_ROOT}/../Examples_3/Unit_Tests/src/01_Transformations/01_Transformations.cpp")
add_executable(01_Transformations "${FORGE_EXAMPLE_SRC}")

if(UNIX)
    # GNU ld hazard, Linux/Release-only: Utilities<->OS<->Renderer<->Application<->Scripting form a
    # dependency diamond, and CMake's own link-line generator defends against it by repeating the
    # flattened list once. That single repeat is enough for linux-gcc-dev (Debug) but NOT for
    # linux-gcc-prod (Release) — real failure: "undefined reference to `_PrintUnicode'/
    # `_FailedAssertImpl'/`_OutputDebugString'" (real OS/Linux/LinuxLog.c symbols). Root cause: GNU ld
    # resolves archives in a single left-to-right pass, only pulling a member when something
    # already-undefined needs it; -O3/NDEBUG shifts exactly which translation unit first references a
    # given Utilities logging symbol, and in Release that reference lands too late in the repeated
    # list for a single repeat to resolve it — Debug's object code just doesn't hit this ordering, not
    # something to rely on continuing to hold. -Wl,--start-group/--end-group tells GNU ld to keep
    # re-scanning every archive in the group until nothing further resolves, independent of how many
    # times CMake's own heuristic repeats the list. MSVC's link.exe has no equivalent need (not
    # single-pass), hence Windows-only guard here.
    target_link_libraries(01_Transformations PRIVATE
        -Wl,--start-group
        Utilities
        OS
        Renderer
        Application
        Scripting
        -Wl,--end-group
    )
else()
    target_link_libraries(01_Transformations PRIVATE
        Utilities
        OS
        Renderer
        Application
        Scripting
    )
endif()

if(WIN32)
    # D3D12_AGILITY_SDK_VERSION gates IApp.h's DEFINE_APPLICATION_MAIN macro, which exports
    # D3D12SDKVersion/D3D12SDKPath — required for D3D12CreateDevice to pick up the vendored Agility
    # SDK redistributable rather than falling back to whatever D3D12 core the OS ships (which can
    # reject a real adapter outright). 715 matches TF_Shared.props' own value — NOT d3d12.h's own
    # D3D12_SDK_VERSION=614, a different, unrelated constant.
    target_compile_definitions(01_Transformations PRIVATE D3D12_AGILITY_SDK_VERSION=715)
    # winmm: same reasoning as AssetPipeline — WindowsWindow.cpp's own #pragma comment(lib,
    # "WinMM.lib") only fires if that specific .obj gets pulled from OS.lib. Linked explicitly here
    # too, even though this example does create a real window.
    target_link_libraries(01_Transformations PRIVATE winmm)
elseif(UNIX)
    # libvulkan.so — the system Vulkan loader (apt's libvulkan-dev/libvulkan1), not a vendored copy;
    # ForgeSrc's own Graphics/ThirdParty/OpenSource/VulkanSDK/bin/Linux/ only carries
    # glslangValidator + the validation layer, never the loader itself. Linked at this executable's
    # own level, not Renderer's — Renderer/CMakeLists.txt itself links no Vulkan loader.
    target_link_libraries(01_Transformations PRIVATE vulkan)
endif()

# --- FSL shader compilation -----------------------------------------------------------------------
# VULKAN's own output has no ".rootsig" file (root signatures are a D3D12-only concept) — otherwise
# identical basenames to DIRECT3D12, just under a VULKAN/ subdirectory instead.
if(WIN32)
    set(FSL_PYTHON_EXE "${CMAKE_CURRENT_SOURCE_DIR}/../../ForgeSrc/Tools/python-3.6.0-embed-amd64/python.exe")
    set(FSL_PLATFORM DIRECT3D12)
elseif(UNIX)
    set(FSL_PYTHON_EXE python3)
    set(FSL_PLATFORM VULKAN)
endif()
set(FSL_SCRIPT "${FORGE_ROOT}/Tools/ForgeShadingLanguage/fsl.py")
set(SHADERS_LIST "${CMAKE_CURRENT_SOURCE_DIR}/../../ForgeSrc/Examples_3/Unit_Tests/src/01_Transformations/Shaders/FSL/shaders.list")
set(SHADER_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/ShadersGenerated")
set(SHADER_BIN_DIR "${CMAKE_CURRENT_BINARY_DIR}/Shaders")

if(WIN32)
    set(01_TRANSFORMATIONS_SHADER_OUTPUTS
        "${SHADER_BIN_DIR}/${FSL_PLATFORM}/default.rootsig"
        "${SHADER_BIN_DIR}/${FSL_PLATFORM}/basic.vert"
        "${SHADER_BIN_DIR}/${FSL_PLATFORM}/basic.frag"
        "${SHADER_BIN_DIR}/${FSL_PLATFORM}/skybox.vert"
        "${SHADER_BIN_DIR}/${FSL_PLATFORM}/skybox.frag"
    )
else()
    set(01_TRANSFORMATIONS_SHADER_OUTPUTS
        "${SHADER_BIN_DIR}/${FSL_PLATFORM}/basic.vert"
        "${SHADER_BIN_DIR}/${FSL_PLATFORM}/basic.frag"
        "${SHADER_BIN_DIR}/${FSL_PLATFORM}/skybox.vert"
        "${SHADER_BIN_DIR}/${FSL_PLATFORM}/skybox.frag"
    )
endif()

add_custom_command(
    OUTPUT ${01_TRANSFORMATIONS_SHADER_OUTPUTS}
    COMMAND ${CMAKE_COMMAND} -E make_directory "${SHADER_GEN_DIR}" "${SHADER_BIN_DIR}"
    COMMAND ${FSL_ENV_ARGS} "${FSL_PYTHON_EXE}" "${FSL_SCRIPT}"
        -d "${SHADER_GEN_DIR}"
        -b "${SHADER_BIN_DIR}"
        -l ${FSL_PLATFORM}
        ${FSL_INCLUDE_ARGS}
        --compile
        "${SHADERS_LIST}"
    DEPENDS "${SHADERS_LIST}"
    COMMENT "Compiling 01_Transformations shaders via FSL (${FSL_PLATFORM})"
    VERBATIM
)
add_custom_target(01_TransformationsShaders DEPENDS ${01_TRANSFORMATIONS_SHADER_OUTPUTS})
add_dependencies(01_Transformations 01_TransformationsShaders)

# initScreenshotCapturer/initUserInterface/initFontSystem (Application/Screenshot, Application/UI,
# Application/Fonts) are all called unconditionally from every real app's own Init(), and each needs
# its own shared FSL shaders (copy.comp, imgui.*, fontstash.*) that aren't part of this example's own
# shaders.list above. Compiled once for every example, not per-example, by cmake/forge-shaders.cmake.
forge_copy_shared_app_shaders(01_Transformations "${SHADER_BIN_DIR}/${FSL_PLATFORM}")

# --- runtime content -------------------------------------------------------------------------------
# PathStatement.txt maps RD_SHADER_BINARIES/RD_GPU_CONFIG only — every other resource directory
# (RD_TEXTURES, RD_FONTS, ...) is left unmapped, resolving to plain CWD (next to the exe), so the
# skybox textures/font below are copied flat/by-relative-name rather than into a dedicated subtree.
# The same file is reused as-is on both platforms — it names no platform-specific subdirectory.
add_custom_command(TARGET 01_Transformations POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/PathStatement.txt"
        "$<TARGET_FILE_DIR:01_Transformations>"
)

if(WIN32)
    forge_copy_runtime_dlls(01_Transformations)
    forge_copy_gpu_data(01_Transformations)
elseif(UNIX)
    # Linux analog of forge-runtime.cmake's forge_copy_gpu_data() (that file is D3D12-vendor-lib-
    # specific and Windows-only, so it has no gpu.data branch to reuse here). steamdeck_gpu.data is
    # Forge's own vendored Linux/Vulkan preset-tier database, read the same way as gpu.data
    # (GraphicsConfig.cpp's initGPUConfiguration, RD_OTHER_FILES, regardless of backend). Only one
    # example exists on Linux so far — inlined here rather than factored into a shared cmake/ file;
    # revisit if a second Linux example needs the same two steps.
    add_custom_command(TARGET 01_Transformations POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${FORGE_ROOT}/OS/Linux/steamdeck_gpu.data"
            "$<TARGET_FILE_DIR:01_Transformations>/gpu.data"
    )
    # Vulkan validation layer (.so + .json) — not required for the loader itself (that's the system
    # libvulkan linked above), only for VK_LAYER_KHRONOS_validation to be discoverable via
    # VK_LAYER_PATH-less same-directory lookup when a debug/validation build enables it.
    add_custom_command(TARGET 01_Transformations POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/VulkanSDK/bin/Linux/libVkLayer_khronos_validation.so"
            "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/VulkanSDK/bin/Linux/VkLayer_khronos_validation.json"
            "$<TARGET_FILE_DIR:01_Transformations>"
    )
endif()

# Skybox textures (RD_TEXTURES unmapped -> CWD) and font (RD_FONTS unmapped -> CWD, and the
# example's own FontDesc::pFontPath is itself "TitilliumText/TitilliumText-Bold.otf", hence the
# matching subdirectory here) — fetched from Forge's own Art.zip (http://www.conffx.com/Art.zip),
# Art/Textures/dds/. Always dds/, never the sibling ktx/ directory that also exists in the zip —
# every real desktop platform (Windows, SteamOS/Linux, MacOS) maps RD_TEXTURES at dds/; only
# Android/iOS use a separately-prepared texture set.
set(FORGE_ART_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../ForgeSrc/Art")
add_custom_command(TARGET 01_Transformations POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${FORGE_ART_ROOT}/Textures/dds/Skybox_right1.tex"
        "${FORGE_ART_ROOT}/Textures/dds/Skybox_left2.tex"
        "${FORGE_ART_ROOT}/Textures/dds/Skybox_top3.tex"
        "${FORGE_ART_ROOT}/Textures/dds/Skybox_bottom4.tex"
        "${FORGE_ART_ROOT}/Textures/dds/Skybox_front5.tex"
        "${FORGE_ART_ROOT}/Textures/dds/Skybox_back6.tex"
        "$<TARGET_FILE_DIR:01_Transformations>"
    COMMAND ${CMAKE_COMMAND} -E make_directory
        "$<TARGET_FILE_DIR:01_Transformations>/TitilliumText"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${FORGE_ART_ROOT}/Fonts/TitilliumText/TitilliumText-Bold.otf"
        "$<TARGET_FILE_DIR:01_Transformations>/TitilliumText"
)
