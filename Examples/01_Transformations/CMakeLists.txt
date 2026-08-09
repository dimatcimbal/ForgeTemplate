# The first real end-to-end example — mirrors Examples_3/Unit_Tests/src/01_Transformations verbatim
# (a single unmodified vendored .cpp), the first proof this template's whole stack actually links and
# runs, not just builds. Uses Forge's own real IApp/DEFINE_APPLICATION_MAIN/WindowsMain(/LinuxMain on
# Linux) application framework directly — not a custom bootstrap, since this is upstream's own real
# example file, unmodified.
#
# Builds on both Windows (D3D12) and Linux (Vulkan) — confirmed directly against upstream's own real
# SteamOS_CodeLite/01_Transformations.project (a genuine Linux/Vulkan build of this exact example
# upstream ships), not something this template invented. Branched if(WIN32)/if(UNIX) inline in this
# one file rather than split across two, matching this project's own established convention (see OS/
# CMakeLists.txt's own header comment, and cmake/forge-shaders.cmake which this file depends on for
# exactly the same reasoning). Renderer only ever builds one backend per platform (D3D12 on Windows,
# Vulkan on Linux — never both fused, see Renderer/CMakeLists.txt), so every FSL invocation/link/
# runtime-asset step below has a real per-platform branch, not a Windows-only assumption smuggled in
# unguarded (an earlier version of this file did exactly that — hardcoded "-l DIRECT3D12" and the
# Windows-only embedded python.exe with no if(WIN32) of its own — before Linux support existed here).

# Every module 01_Transformations.cpp's own code actually calls into, listed explicitly rather than
# linking just Scripting and relying on its PUBLIC chain (Scripting -> Application -> Renderer ->
# Utilities/OS) to pull the rest in transitively — real, direct dependencies, not a literal "OS +
# Renderer" pair the .sln lists for 01_Transformations either (that reflects upstream's own coarser
# bundling, Application's files compiling directly into OS.vcxproj upstream; see
# plan/module-split.md's Examples table row):
#   - Utilities: ILog/IFileSystem calls
#   - OS: WindowsMain/LinuxMain (DEFINE_APPLICATION_MAIN's real per-platform entry point)
#   - Renderer: IGraphics calls (addPipeline/addShader/cmdBindPipeline/...)
#   - Application: IUI/IProfiler/IScreenshot calls (initUserInterface/initProfiler/...)
#   - Scripting: WindowsMain/LinuxMain unconditionally calls into Lua scripting hooks (confirmed
#     directly via a real link failure on Windows), not something 01_Transformations.cpp calls itself

set(FORGE_EXAMPLE_SRC "${FORGE_ROOT}/../Examples_3/Unit_Tests/src/01_Transformations/01_Transformations.cpp")
add_executable(01_Transformations "${FORGE_EXAMPLE_SRC}")

if(UNIX)
    # Real, confirmed-via-a-real-link-failure GNU ld hazard, Linux/Release-only:
    # Utilities<->OS<->Renderer<->Application<->Scripting form a genuine dependency diamond (Renderer
    # PUBLIC-links Utilities+OS, Application PUBLIC-links Utilities+OS+Renderer, Scripting PUBLIC-links
    # Utilities+Application), and CMake's own link-line generator already defends against exactly this
    # by repeating the flattened list once (confirmed directly in build-linux-gcc-dev/build.ninja: the
    # generated link line is "Utilities OS Renderer Application Scripting Application Renderer OS
    # Utilities ..."). That single repeat is enough for linux-gcc-dev (Debug) but NOT for
    # linux-gcc-prod (Release) — confirmed directly via a real failed link ("undefined reference to
    # `_PrintUnicode'/`_FailedAssertImpl'/`_OutputDebugString'", all real symbols OS/Linux/LinuxLog.c
    # genuinely defines, confirmed present via `nm` against the actual archive member built moments
    # earlier). Root cause: GNU ld resolves archives in a single left-to-right pass per occurrence, only
    # pulling a member when something already-undefined needs it; -O3/NDEBUG changes exactly which
    # translation unit's code first references a given Utilities logging symbol (inlining/dead-code
    # elimination shift where in the object graph that reference first appears), and in Release that
    # first reference happens to land in the SECOND repeated group, at a position after OS.a's own
    # second occurrence has already been scanned — so by the time Utilities.a's Log.c.o gets extracted
    # (last item in that group), there's no later OS.a occurrence left to resolve it against, only the
    # system .so libraries that follow. Debug's object code happens not to hit this ordering, purely by
    # luck of what optimization did or didn't inline — not something to rely on continuing to hold.
    # -Wl,--start-group/--end-group is the standard, well-known fix for exactly this class of circular/
    # order-sensitive static-archive link hazard: it tells GNU ld to keep re-scanning every archive
    # inside the group until no further symbols can be resolved, independent of how many times CMake's
    # own heuristic happens to repeat the list. MSVC's link.exe has no equivalent need (a fundamentally
    # different, not single-pass, archive-resolution algorithm), hence Windows-only guard here.
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
    # D3D12SDKVersion/D3D12SDKPath — required for D3D12CreateDevice to actually pick up the vendored
    # Agility SDK redistributable rather than falling back to whatever D3D12 core the OS ships (which
    # can reject a real adapter outright). 715 matches TF_Shared.props' own real
    # D3D12_AGILITY_SDK_VERSION value exactly, confirmed directly against that file — NOT d3d12.h's
    # own D3D12_SDK_VERSION=614, a different, unrelated constant. D3D12-specific, no Linux equivalent.
    target_compile_definitions(01_Transformations PRIVATE D3D12_AGILITY_SDK_VERSION=715)
    # winmm: same reasoning as AssetPipeline — WindowsWindow.cpp's own #pragma comment(lib,
    # "WinMM.lib") only fires if that specific .obj gets pulled from OS.lib, and while this example
    # (unlike AssetPipeline) does create a real window, linking it explicitly here is cheap insurance
    # against the same static-library-only-links-what-it-references trap, not a guess.
    target_link_libraries(01_Transformations PRIVATE winmm)
elseif(UNIX)
    # libvulkan.so itself — confirmed directly against the real SteamOS_CodeLite/
    # 01_Transformations.project's own <Library Value="libvulkan.so"/> entry: a plain, unpathed
    # library name, i.e. the system Vulkan loader (apt's libvulkan-dev/libvulkan1), not a vendored
    # copy — ForgeSrc's own Graphics/ThirdParty/OpenSource/VulkanSDK/bin/Linux/ only carries
    # glslangValidator + the validation layer, never the loader itself (see gotcha in build-agent.md).
    # Linked at this executable's own level, not Renderer's — same "static libs never resolve
    # external symbols until the final link" reasoning already applied to winmm/dxcompiler.lib/etc.
    # above; Renderer/CMakeLists.txt itself links no Vulkan loader for the same reason.
    target_link_libraries(01_Transformations PRIVATE vulkan)
endif()

# --- FSL shader compilation -----------------------------------------------------------------------
# DIRECT3D12 (Windows) uses ForgeSrc's own vendored embeddable Python; VULKAN (Linux) uses system
# python3 — same reasoning, and same confirmed-safe-via-direct-testing basis, as
# cmake/forge-shaders.cmake's own header comment (this example's own shaders.list was one of the
# four real lists tested there). VULKAN's own output has no ".rootsig" file (root signatures are a
# D3D12-only concept) — confirmed directly by running fsl.py -l VULKAN against this exact
# shaders.list in WSL — otherwise identical basenames to DIRECT3D12, just under a VULKAN/
# subdirectory instead.
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
# Application/Fonts) are all called unconditionally from every real app's own Init() — confirmed via a
# live cdb trace of the exact crash this was chasing (see build-agent.md's "Known open issues") — and
# each needs its own shared FSL shaders (copy.comp, imgui.*, fontstash.*) that genuinely aren't part of
# this example's own shaders.list above. Compiled once for every example, not per-example, by
# cmake/forge-shaders.cmake — see that file's own header comment for why (upstream's real shape, and
# avoiding N redundant fsl.py invocations for byte-identical output).
forge_copy_shared_app_shaders(01_Transformations "${SHADER_BIN_DIR}/${FSL_PLATFORM}")

# --- runtime content -------------------------------------------------------------------------------
# PathStatement.txt maps RD_SHADER_BINARIES/RD_GPU_CONFIG only — every other resource directory
# (RD_TEXTURES, RD_FONTS, ...) is left unmapped, resolving to gResourceDirectories' zero-initialized
# default (plain CWD, i.e. next to the exe, confirmed directly against FileSystem.c), so the skybox
# textures/font below are copied flat/by-relative-name rather than into a dedicated subtree. The same
# file is reused as-is on both platforms — it names no platform-specific subdirectory
# ("Shaders/"/"GPUCfg/" resolve identically regardless of DIRECT3D12 vs VULKAN underneath), and the
# strcat-based path-join it depends on (Utilities/FileSystem/FileSystem.c's fsOpenStreamFromPath,
# confirmed directly) is itself platform-neutral C code, not something OS/Windows or OS/Linux
# overrides — so there's no real Linux-flavored variant to write here.
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
    # specific and Windows-only — see root CMakeLists.txt's own comment — so it has no gpu.data
    # branch to reuse here). GraphicsConfig.cpp's initGPUConfiguration reads "gpu.data" from
    # RD_OTHER_FILES regardless of backend (gotcha in build-agent.md); steamdeck_gpu.data is Forge's
    # own real vendored Linux/Vulkan preset-tier database (OS/Linux/steamdeck_gpu.data), confirmed
    # directly against the real SteamOS_CodeLite/01_Transformations.project's own PostBuild rsync
    # step (".../Common_3/OS/Linux/steamdeck_gpu.data" -> "gpu.data"). Only one example exists on
    # Linux so far — inlined here rather than factored into a shared cmake/ file; revisit if a second
    # Linux example needs the same two steps.
    add_custom_command(TARGET 01_Transformations POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${FORGE_ROOT}/OS/Linux/steamdeck_gpu.data"
            "$<TARGET_FILE_DIR:01_Transformations>/gpu.data"
    )
    # Vulkan validation layer (.so + .json) — same real PostBuild step upstream's own
    # SteamOS_CodeLite project performs ("rsync --include '*.so' --include '*.json' --exclude '*'"
    # from this exact vendored directory). Not required for the loader itself (that's the system
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
# matching subdirectory here) — fetched from Forge's own real Art.zip
# (http://www.conffx.com/Art.zip, the same download Forge's own PRE_BUILD.bat performs), Art/
# Textures/dds/ — confirmed directly against every real desktop PathStatement.*.txt shipped inside
# Art.zip itself (Windows, SteamOS/Linux, *and* MacOS all map RD_TEXTURES at .../Art/Textures/dds/,
# never a ktx/ sibling — that directory exists in the zip but no real desktop PathStatement.*.txt
# actually references it; only Android/iOS bundle a separately-prepared texture set, not this loose-
# file mechanism at all). A prior version of this comment guessed "ktx/ for Vulkan/GLES" without
# checking the real file — corrected here since Examples/01_Transformations now builds on Linux too
# and reuses this exact same dds/ set (see the if(UNIX) block below).
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
