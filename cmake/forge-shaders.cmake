# Compiles Application's own shared FSL shader lists (Screenshot/UI/Fonts) exactly once per configure,
# regardless of how many Examples/* end up needing them — matching upstream's own real shape (its
# OS.vcxproj, which subsumes what this template calls Application, compiles these once and copies the
# result into every example's own output; confirmed directly, every ForgeSrc PC_VS2019 example's own
# prebuilt CompiledShaders/DIRECT3D12/ carries byte-identical copy.comp/imgui.*/fontstash.* files) —
# not recompiled by each Examples/<Name>/CMakeLists.txt separately, which would be N redundant fsl.py
# invocations for identical output, plus N copies of near-identical add_custom_command boilerplate to
# keep in sync by hand. Included from root CMakeLists.txt unconditionally (both platforms) — one file
# with if(WIN32)/elseif(UNIX) branching inside, matching the project-wide convention (see OS/
# CMakeLists.txt's own header comment) rather than splitting into per-backend files; see this repo's
# own build-agent.md for why that split was considered and rejected.
#
# initScreenshotCapturer/initUserInterface/initFontSystem (Application/Screenshot, Application/UI,
# Application/Fonts) are all called unconditionally from every real app's own Init() — confirmed via
# live cdb traces of 01_Transformations's own real crash (see build-agent.md's "Known open issues"),
# not something any example's own shaders.list ever declares itself.
#
# DIRECT3D12 (Windows) uses ForgeSrc's own vendored embeddable Python (no system Python dependency);
# VULKAN (Linux) uses system `python3` instead — confirmed directly (fsl.py itself is a portable
# script, nothing Windows-specific in it) and matches upstream's own real SteamOS_CodeLite build
# recipe exactly (`python3 .../fsl.py -l VULKAN ...`). Neither platform needs any FSL_COMPILER_*
# environment variable set explicitly — fsl.py's own top-of-file defaults already point
# FSL_COMPILER_DXC/FSL_COMPILER_VK/FSL_COMPILER_LINUX_VK at the matching vendored compiler
# (DirectXShaderCompiler/bin/x64, VulkanSDK/bin/Win32, VulkanSDK/bin/Linux respectively) whenever
# they're not already set — confirmed directly by running fsl.py standalone against all three real
# Application shader lists plus 01_Transformations's own shaders.list in WSL, zero errors, zero extra
# setup. VULKAN's own final output filenames match DIRECT3D12's exactly (no "_0.spv" derivative
# suffix on the canonical file — same "_N.<ext>" intermediate-then-renamed pattern both backends
# share), confirmed the same way — only the subdirectory name differs (VULKAN/ vs DIRECT3D12/).
if(WIN32)
    set(FSL_PYTHON_EXE "${CMAKE_SOURCE_DIR}/ForgeSrc/Tools/python-3.6.0-embed-amd64/python.exe")
    set(FSL_PLATFORM DIRECT3D12)
elseif(UNIX)
    set(FSL_PYTHON_EXE python3)
    set(FSL_PLATFORM VULKAN)
endif()
set(FSL_SCRIPT "${FORGE_ROOT}/Tools/ForgeShadingLanguage/fsl.py")

# Real, confirmed-only-via-actual-CI (not local WSL, and not even a native-ext4 `rsync` copy of a
# DrvFs-backed WSL checkout — see gotcha in build-agent.md) upstream packaging gap: ForgeSrc's own
# vendored Common_3/Graphics/ThirdParty/OpenSource/VulkanSDK/bin/Linux/glslangValidator is committed
# with git file mode 100644 (not executable), confirmed directly via `git ls-files -s` against the
# real submodule checkout — compilers.py's own get_compiler_from_env() joins FSL_COMPILER_LINUX_VK
# with this exact filename and hands it straight to subprocess.run([bin] + params, ...), which needs
# real execute permission, not just read. A genuine `git checkout` on a real filesystem (GitHub
# Actions' own ubuntu-24.04 runner) applies that 100644 mode faithfully and the subprocess call fails
# outright with PermissionError: [Errno 13]; Windows has no POSIX exec bit to violate, and this
# template's own local WSL testing (both a /mnt/c-backed checkout and an `rsync`-to-native-ext4 copy,
# since `rsync -a` preserves the *source*'s apparent permissions, and DrvFs's own default
# non-metadata mode presents every file as executable regardless of what git actually tracked)
# happened to mask this the same structural way gotcha #16 already documents for case-sensitivity —
# a third, distinct instance of "this dev machine's WSL setup isn't a faithful proxy for a real
# `git checkout` on Linux," not a one-off surprise. ForgeSrc is never edited, so the fix isn't a
# chmod on the vendored file itself (that would show up as a real, if uncommitted, mode-change the
# next time anyone runs `git -C ForgeSrc status`) — instead, copy just this one binary into the build
# directory (gitignored, zero ForgeSrc footprint, same "shim in the build dir, never touch the
# submodule" precedent as FSL_INCLUDE_ARGS below) and fix the permission bit on that copy alone, then
# override FSL_COMPILER_LINUX_VK to point there for every real FSL invocation on Linux via
# `cmake -E env` (a real, portable, shell-free way to set an env var around one COMMAND). Only
# glslangValidator itself needs this — the sibling libVkLayer_khronos_validation.so/.json in the same
# vendored directory are runtime-only assets (dlopen'd by the Vulkan loader, which doesn't require the
# execute bit the way a direct subprocess execve() does), copied as-is by Examples/01_Transformations's
# own POST_BUILD step, not touched here.
set(FSL_ENV_ARGS "")
if(UNIX)
    set(FSL_VULKAN_COMPILER_DIR "${CMAKE_BINARY_DIR}/fsl-vulkan-compiler")
    file(COPY "${FORGE_ROOT}/Graphics/ThirdParty/OpenSource/VulkanSDK/bin/Linux/glslangValidator"
        DESTINATION "${FSL_VULKAN_COMPILER_DIR}")
    file(CHMOD "${FSL_VULKAN_COMPILER_DIR}/glslangValidator"
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                     GROUP_READ GROUP_EXECUTE
                     WORLD_READ WORLD_EXECUTE)
    # fsl.py's own top-level default-setting code (not compilers.py) only guards on
    # `if not 'FSL_COMPILER_VK' in os.environ:` before setting *both* FSL_COMPILER_VK and
    # FSL_COMPILER_LINUX_VK to their vendored defaults — confirmed directly, the hard way, by a first
    # attempt that set only FSL_COMPILER_LINUX_VK and had it silently clobbered straight back to the
    # unfixed vendored path every time. FSL_COMPILER_VK's own value is never actually read on Linux
    # (compilers.py's get_compiler_from_env() substitutes FSL_COMPILER_LINUX_VK in its place whenever
    # sys.platform == 'linux'), but it must still be *present* in the environment, any value, purely to
    # satisfy that guard and stop fsl.py from overwriting the real one this override actually needs.
    set(FSL_ENV_ARGS ${CMAKE_COMMAND} -E env
        "FSL_COMPILER_VK=${FSL_VULKAN_COMPILER_DIR}"
        "FSL_COMPILER_LINUX_VK=${FSL_VULKAN_COMPILER_DIR}")
endif()

# Real, confirmed-only-via-actual-CI (not local WSL) case-sensitivity bug class, same root cause as
# gotcha #13 (Application/CMakeLists.txt's own C++ -iquote shims) but a genuinely different mechanism:
# fsl.py's own utils.py (collect_shader_decl) resolves every FSL #include by piping the .list/.fsl
# source through a REAL preprocessor — `cc -E -` on non-Windows (confirmed directly reading utils.py),
# with "-I<the including file's own directory>" passed first, then any extra -I dirs this script adds
# below. Several real vendored .list/.fsl files reference their own sibling files with different case
# than what's actually on disk (Copy.comp.fsl vs. real copy.comp.fsl, ImGui.frag.fsl vs. real
# imgui.frag.fsl, FontStash*.fsl vs. real fontstash*.fsl, Resources.h vs. real resources.h,
# FontStash.srt.h vs. real fontstash.srt.h, Basic/Skybox*.fsl vs. real basic/skybox*.fsl,
# Resources.h.fsl vs. real resources.h.fsl — enumerated by walking the full include graph directly,
# not guessed one CI round-trip at a time this time, see build-agent.md gotcha for the full table).
# Silently fine on Windows (case-insensitive NTFS) *and*, critically, silently fine on this repo's own
# local WSL testing too — WSL's repo checkout lives on /mnt/c (NTFS via DrvFs), which is
# case-INsensitive exactly like real Windows, so no amount of local `wsl` rebuilding could ever have
# caught this; only a genuinely native Linux filesystem (this template's own GitHub Actions
# ubuntu-24.04 runner, a real ext4 checkout) surfaces it. Same shim technique as gotcha #13 in spirit
# (a one-line forwarding file placed where the real lookup already fails, never touching ForgeSrc's own
# tree) but implemented via fsl.py's own "-I"/"--includes" passthrough rather than a compiler's
# -iquote, since the responsible tool here is fsl.py's own subprocess call, not a C++ target's own
# compile_options. One shared shim directory/variable (FSL_INCLUDE_ARGS) for every FSL invocation in
# this project — both this file's own 3 SharedAppShaders commands and Examples/01_Transformations's own
# shaders.list command all pass it, since a couple of these mismatches recur verbatim in both places'
# own include graphs (e.g. the "Resources.h"-family pattern) and there's no reason to duplicate the
# shim-generation logic per call site.
set(FSL_INCLUDE_ARGS "")
if(UNIX)
    set(FSL_SHIM_DIR "${CMAKE_BINARY_DIR}/fsl-generated-includes")
    set(_forge_fsl_shims
        "Copy.comp.fsl|${FORGE_ROOT}/Application/Screenshot/Shaders/FSL/copy.comp.fsl"
        "Copy.comp.srt.h|${FORGE_ROOT}/Application/Screenshot/Shaders/FSL/copy.comp.srt.h"
        "ImGui.frag.fsl|${FORGE_ROOT}/Application/UI/Shaders/FSL/imgui.frag.fsl"
        "ImGui.vert.fsl|${FORGE_ROOT}/Application/UI/Shaders/FSL/imgui.vert.fsl"
        "FontStash.frag.fsl|${FORGE_ROOT}/Application/Fonts/Shaders/FSL/fontstash.frag.fsl"
        "FontStash2D.vert.fsl|${FORGE_ROOT}/Application/Fonts/Shaders/FSL/fontstash2D.vert.fsl"
        "FontStash3D.vert.fsl|${FORGE_ROOT}/Application/Fonts/Shaders/FSL/fontstash3D.vert.fsl"
        "Resources.h|${FORGE_ROOT}/Application/Fonts/Shaders/FSL/resources.h"
        "FontStash.srt.h|${FORGE_ROOT}/Application/Fonts/Shaders/FSL/fontstash.srt.h"
        "Basic.frag.fsl|${FORGE_ROOT}/../Examples_3/Unit_Tests/src/01_Transformations/Shaders/FSL/basic.frag.fsl"
        "Basic.vert.fsl|${FORGE_ROOT}/../Examples_3/Unit_Tests/src/01_Transformations/Shaders/FSL/basic.vert.fsl"
        "Skybox.frag.fsl|${FORGE_ROOT}/../Examples_3/Unit_Tests/src/01_Transformations/Shaders/FSL/skybox.frag.fsl"
        "Skybox.vert.fsl|${FORGE_ROOT}/../Examples_3/Unit_Tests/src/01_Transformations/Shaders/FSL/skybox.vert.fsl"
        "Resources.h.fsl|${FORGE_ROOT}/../Examples_3/Unit_Tests/src/01_Transformations/Shaders/FSL/resources.h.fsl"
    )
    foreach(_forge_fsl_shim ${_forge_fsl_shims})
        string(REPLACE "|" ";" _forge_fsl_shim_parts "${_forge_fsl_shim}")
        list(GET _forge_fsl_shim_parts 0 _forge_fsl_shim_name)
        list(GET _forge_fsl_shim_parts 1 _forge_fsl_shim_target)
        set(_forge_fsl_shim_path "${FSL_SHIM_DIR}/${_forge_fsl_shim_name}")
        if(NOT EXISTS "${_forge_fsl_shim_path}")
            file(WRITE "${_forge_fsl_shim_path}" "#include \"${_forge_fsl_shim_target}\"\n")
        endif()
    endforeach()
    set(FSL_INCLUDE_ARGS -I "${FSL_SHIM_DIR}")
endif()

set(SHARED_APP_SHADER_GEN_DIR "${CMAKE_BINARY_DIR}/SharedAppShaders/ShadersGenerated")
set(SHARED_APP_SHADER_BIN_DIR "${CMAKE_BINARY_DIR}/SharedAppShaders/Shaders")

set(SCREENSHOT_SHADERS_LIST "${FORGE_ROOT}/Application/Screenshot/Shaders/FSL/ScreenshotShaders.list")
set(UI_SHADERS_LIST "${FORGE_ROOT}/Application/UI/Shaders/FSL/UIShaders.list")
set(FONT_SHADERS_LIST "${FORGE_ROOT}/Application/Fonts/Shaders/FSL/FontShaders.list")

# Full output list, cross-checked directly against each .list's own #comp/#vert/#frag directives
# (Application/Screenshot/Shaders/FSL/ScreenshotShaders.list, Application/UI/Shaders/FSL/
# UIShaders.list, Application/Fonts/Shaders/FSL/FontShaders.list) — not guessed from the crash trace
# alone, which only ever surfaces the *first* missing file per rebuild, one at a time. Identical
# basenames on both platforms (confirmed directly), only ${FSL_PLATFORM} (the subdirectory) differs.
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
# <target> depend on SharedAppShaders (build-order correctness — compiled once, first time any target
# needs it) and copies every shared shader file into dest_dir (that example's own
# "<its-own-SHADER_BIN_DIR>/${FSL_PLATFORM}", passed explicitly rather than assumed/hardcoded here,
# since this file has no reason to know any example's own folder-naming convention).
function(forge_copy_shared_app_shaders target dest_dir)
    add_dependencies(${target} SharedAppShaders)
    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${dest_dir}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SHARED_APP_SHADER_FILES} "${dest_dir}"
    )
endfunction()
