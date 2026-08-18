# Compiles Application's own shared FSL shader lists (Screenshot/UI/Fonts) exactly once per configure,
# not per Examples/* — matching upstream's own real shape (every ForgeSrc PC_VS2019 example's own
# prebuilt CompiledShaders/DIRECT3D12/ carries byte-identical copy.comp/imgui.*/fontstash.* files).
# Included from root CMakeLists.txt unconditionally (both platforms), if(WIN32)/elseif(UNIX) branched
# inline in this one file.
#
# initScreenshotCapturer/initUserInterface/initFontSystem (Application/Screenshot, Application/UI,
# Application/Fonts) are all called unconditionally from every real app's own Init() — not something
# any example's own shaders.list ever declares itself.
#
# DIRECT3D12 (Windows) uses ForgeSrc's own vendored embeddable Python (no system Python dependency);
# VULKAN (Linux) uses system python3, matching upstream's own real SteamOS_CodeLite build recipe.
# Neither platform needs any FSL_COMPILER_* environment variable set explicitly — fsl.py's own
# top-of-file defaults already point at the matching vendored compiler whenever not already set.
# VULKAN's own final output filenames match DIRECT3D12's exactly, only the subdirectory name differs
# (VULKAN/ vs DIRECT3D12/).
if(WIN32)
    set(FSL_PYTHON_EXE "${CMAKE_SOURCE_DIR}/ForgeSrc/Tools/python-3.6.0-embed-amd64/python.exe")
    set(FSL_PLATFORM DIRECT3D12)
elseif(UNIX)
    set(FSL_PYTHON_EXE python3)
    set(FSL_PLATFORM VULKAN)
endif()
set(FSL_SCRIPT "${FORGE_ROOT}/Tools/ForgeShadingLanguage/fsl.py")

# ForgeSrc's own vendored VulkanSDK/bin/Linux/glslangValidator is committed with git file mode 100644
# (not executable) — compilers.py's own get_compiler_from_env() hands it straight to
# subprocess.run([bin] + params, ...), which needs real execute permission, not just read. ForgeSrc
# is never edited, so the fix isn't a chmod on the vendored file itself — instead, copy just this one
# binary into the build directory (gitignored) and fix the permission bit on that copy alone, then
# override FSL_COMPILER_LINUX_VK to point there for every FSL invocation on Linux via `cmake -E env`.
# Only glslangValidator itself needs this — the sibling libVkLayer_khronos_validation.so/.json in the
# same vendored directory are runtime-only assets (dlopen'd by the Vulkan loader, which doesn't
# require the execute bit the way a direct subprocess execve() does), copied as-is by
# Examples/01_Transformations's own POST_BUILD step, not touched here.
set(FSL_ENV_ARGS "")
if(UNIX)
    set(FSL_VULKAN_COMPILER_DIR "${CMAKE_BINARY_DIR}/fsl-vulkan-compiler")
    file(COPY "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/VulkanSDK/bin/Linux/glslangValidator"
        DESTINATION "${FSL_VULKAN_COMPILER_DIR}")
    file(CHMOD "${FSL_VULKAN_COMPILER_DIR}/glslangValidator"
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                     GROUP_READ GROUP_EXECUTE
                     WORLD_READ WORLD_EXECUTE)
    # fsl.py's own top-level default-setting code only guards on
    # `if not 'FSL_COMPILER_VK' in os.environ:` before setting *both* FSL_COMPILER_VK and
    # FSL_COMPILER_LINUX_VK back to their vendored defaults — so FSL_COMPILER_VK must also be set
    # (its value is never actually read on Linux) purely to stop fsl.py from clobbering the real
    # override below.
    set(FSL_ENV_ARGS ${CMAKE_COMMAND} -E env
        "FSL_COMPILER_VK=${FSL_VULKAN_COMPILER_DIR}"
        "FSL_COMPILER_LINUX_VK=${FSL_VULKAN_COMPILER_DIR}")
endif()

# fsl.py's own utils.py (collect_shader_decl) resolves every FSL #include by piping the .list/.fsl
# source through a real preprocessor (`cc -E -` on non-Windows), with
# "-I<the including file's own directory>" passed first, then any extra -I dirs this script adds
# below. Several vendored .list/.fsl files reference their own sibling files with different case than
# what's actually on disk — silently fine on Windows (case-insensitive NTFS), a hard failure on
# Linux. Fixed the same way as Application/CMakeLists.txt's own C++ -iquote shims (a one-line
# forwarding file placed where the real lookup fails, never touching ForgeSrc's own tree), just via
# fsl.py's own "-I"/"--includes" passthrough instead of a compiler's -iquote. One shared shim
# directory/variable (FSL_INCLUDE_ARGS) for every FSL invocation in this project — this file's own 3
# SharedAppShaders commands and Examples/01_Transformations's own shaders.list command all pass it.
# forge_write_fsl_shim(<shim name> <real target>) is a plain positional-argument function — each call
# below reads as a single, self-contained "this wrong-case name forwards to this real file" statement.
function(forge_write_fsl_shim shim_name real_target)
    set(_forge_fsl_shim_path "${FSL_SHIM_DIR}/${shim_name}")
    if(NOT EXISTS "${_forge_fsl_shim_path}")
        file(WRITE "${_forge_fsl_shim_path}" "#include \"${real_target}\"\n")
    endif()
endfunction()

set(FSL_INCLUDE_ARGS "")
if(UNIX)
    set(FSL_SHIM_DIR "${CMAKE_BINARY_DIR}/fsl-generated-includes")

    # ScreenshotShaders.list -> Copy.comp.fsl vs. real copy.comp.fsl -> Copy.comp.srt.h vs. real
    # copy.comp.srt.h
    forge_write_fsl_shim(Copy.comp.fsl "${FORGE_ROOT}/Application/Screenshot/Shaders/FSL/copy.comp.fsl")
    forge_write_fsl_shim(Copy.comp.srt.h "${FORGE_ROOT}/Application/Screenshot/Shaders/FSL/copy.comp.srt.h")

    # UIShaders.list -> ImGui.frag.fsl/ImGui.vert.fsl vs. real imgui.frag.fsl/imgui.vert.fsl
    forge_write_fsl_shim(ImGui.frag.fsl "${FORGE_ROOT}/Application/UI/Shaders/FSL/imgui.frag.fsl")
    forge_write_fsl_shim(ImGui.vert.fsl "${FORGE_ROOT}/Application/UI/Shaders/FSL/imgui.vert.fsl")

    # FontShaders.list -> FontStash*.fsl vs. real fontstash*.fsl -> Resources.h vs. real resources.h,
    # one hop further -> FontStash.srt.h vs. real fontstash.srt.h
    forge_write_fsl_shim(FontStash.frag.fsl "${FORGE_ROOT}/Application/Fonts/Shaders/FSL/fontstash.frag.fsl")
    forge_write_fsl_shim(FontStash2D.vert.fsl "${FORGE_ROOT}/Application/Fonts/Shaders/FSL/fontstash2D.vert.fsl")
    forge_write_fsl_shim(FontStash3D.vert.fsl "${FORGE_ROOT}/Application/Fonts/Shaders/FSL/fontstash3D.vert.fsl")
    forge_write_fsl_shim(Resources.h "${FORGE_ROOT}/Application/Fonts/Shaders/FSL/resources.h")
    forge_write_fsl_shim(FontStash.srt.h "${FORGE_ROOT}/Application/Fonts/Shaders/FSL/fontstash.srt.h")

    # 01_Transformations's own shaders.list -> Basic/Skybox*.fsl vs. real basic/skybox*.fsl, and
    # basic.vert.fsl/skybox*.fsl -> Resources.h.fsl vs. real resources.h.fsl
    set(_forge_01t_fsl_dir "${FORGE_ROOT}/../Examples_3/Unit_Tests/src/01_Transformations/Shaders/FSL")
    forge_write_fsl_shim(Basic.frag.fsl "${_forge_01t_fsl_dir}/basic.frag.fsl")
    forge_write_fsl_shim(Basic.vert.fsl "${_forge_01t_fsl_dir}/basic.vert.fsl")
    forge_write_fsl_shim(Skybox.frag.fsl "${_forge_01t_fsl_dir}/skybox.frag.fsl")
    forge_write_fsl_shim(Skybox.vert.fsl "${_forge_01t_fsl_dir}/skybox.vert.fsl")
    forge_write_fsl_shim(Resources.h.fsl "${_forge_01t_fsl_dir}/resources.h.fsl")

    set(FSL_INCLUDE_ARGS -I "${FSL_SHIM_DIR}")
endif()

set(SHARED_APP_SHADER_GEN_DIR "${CMAKE_BINARY_DIR}/SharedAppShaders/ShadersGenerated")
set(SHARED_APP_SHADER_BIN_DIR "${CMAKE_BINARY_DIR}/SharedAppShaders/Shaders")

set(SCREENSHOT_SHADERS_LIST "${FORGE_ROOT}/Application/Screenshot/Shaders/FSL/ScreenshotShaders.list")
set(UI_SHADERS_LIST "${FORGE_ROOT}/Application/UI/Shaders/FSL/UIShaders.list")
set(FONT_SHADERS_LIST "${FORGE_ROOT}/Application/Fonts/Shaders/FSL/FontShaders.list")

# Full output list, cross-checked against each .list's own #comp/#vert/#frag directives — not just
# the first missing file a rebuild's own crash trace happens to surface (check the .list itself when
# adding a new shared shader). Identical basenames on both platforms, only ${FSL_PLATFORM} (the
# subdirectory) differs.
set(SHARED_APP_SHADER_FILES
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/copy.comp"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_1.frag"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_2.frag"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_4.frag"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_8.frag"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_16.frag"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui.vert"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/textured_mesh.frag"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/textured_mesh.vert"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/fontstash.frag"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/fontstash2D.vert"
    "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/fontstash3D.vert"
)

add_custom_command(
    OUTPUT "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/copy.comp"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${SHARED_APP_SHADER_GEN_DIR}" "${SHARED_APP_SHADER_BIN_DIR}"
    COMMAND ${FSL_ENV_ARGS} "${FSL_PYTHON_EXE}" "${FSL_SCRIPT}"
        -d "${SHARED_APP_SHADER_GEN_DIR}"
        -b "${SHARED_APP_SHADER_BIN_DIR}"
        -l ${FSL_PLATFORM}
        ${FSL_INCLUDE_ARGS}
        --compile
        "${SCREENSHOT_SHADERS_LIST}"
    DEPENDS "${SCREENSHOT_SHADERS_LIST}"
    COMMENT "Compiling shared Screenshot capturer shader (copy.comp) via FSL (${FSL_PLATFORM})"
    VERBATIM
)

add_custom_command(
    OUTPUT
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_1.frag"
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_2.frag"
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_4.frag"
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_8.frag"
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui_SAMPLE_COUNT_16.frag"
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/imgui.vert"
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/textured_mesh.frag"
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/textured_mesh.vert"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${SHARED_APP_SHADER_GEN_DIR}" "${SHARED_APP_SHADER_BIN_DIR}"
    COMMAND ${FSL_ENV_ARGS} "${FSL_PYTHON_EXE}" "${FSL_SCRIPT}"
        -d "${SHARED_APP_SHADER_GEN_DIR}"
        -b "${SHARED_APP_SHADER_BIN_DIR}"
        -l ${FSL_PLATFORM}
        ${FSL_INCLUDE_ARGS}
        --compile
        "${UI_SHADERS_LIST}"
    DEPENDS "${UI_SHADERS_LIST}"
    COMMENT "Compiling shared UI (imgui) shaders via FSL (${FSL_PLATFORM})"
    VERBATIM
)

add_custom_command(
    OUTPUT
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/fontstash.frag"
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/fontstash2D.vert"
        "${SHARED_APP_SHADER_BIN_DIR}/${FSL_PLATFORM}/fontstash3D.vert"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${SHARED_APP_SHADER_GEN_DIR}" "${SHARED_APP_SHADER_BIN_DIR}"
    COMMAND ${FSL_ENV_ARGS} "${FSL_PYTHON_EXE}" "${FSL_SCRIPT}"
        -d "${SHARED_APP_SHADER_GEN_DIR}"
        -b "${SHARED_APP_SHADER_BIN_DIR}"
        -l ${FSL_PLATFORM}
        ${FSL_INCLUDE_ARGS}
        --compile
        "${FONT_SHADERS_LIST}"
    DEPENDS "${FONT_SHADERS_LIST}"
    COMMENT "Compiling shared Font (fontstash) shaders via FSL (${FSL_PLATFORM})"
    VERBATIM
)

add_custom_target(SharedAppShaders DEPENDS ${SHARED_APP_SHADER_FILES})

# Called by each Examples/<Name>/CMakeLists.txt, after its own FSL shader target is set up: makes
# <target> depend on SharedAppShaders (compiled once, first time any target needs it) and copies
# every shared shader file into dest_dir — passed explicitly since this file has no reason to know
# any example's own folder-naming convention.
function(forge_copy_shared_app_shaders target dest_dir)
    add_dependencies(${target} SharedAppShaders)
    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${dest_dir}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SHARED_APP_SHADER_FILES} "${dest_dir}"
    )
endfunction()
