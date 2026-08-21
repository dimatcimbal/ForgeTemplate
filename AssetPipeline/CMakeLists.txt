# Tools/AssetPipeline + its supporting libraries — the offline content-processing CLI tool
# (AssetPipelineCmd) and everything it alone needs: ozz_animation_offline, ISPC-compiled BC/ASTC
# texture compression kernels, and BunyLib's archive format. ozz_base/ozz_animation (runtime) come
# from the Ozz module instead of being defined here — AssetPipeline needs them too (SkeletonBuilder/
# AnimationBuilder's own operator() returns real ozz::animation::Skeleton/Animation objects, whose
# constructors live in ozz_animation's runtime .cc files, not the offline ones this file's own
# #includes might suggest), but so does Animation/06_MaterialPlayground, cross-platform.
#
# Windows only — upstream's own SteamOS_CodeLite (Linux) build doesn't include AssetPipeline/
# ozz_animation_offline/BunyLib/ispc_texcomp at all, only PC_VS2019 does. Porting to Linux would mean
# inventing the ISPC custom-build step (object format, target-ISA flags) with no precedent to verify
# against.
#
# Depends on Utilities + OS in full, not just Utilities — headless in the sense of never opening a
# window, not in the sense of no OS dependency.
#
# The internal libraries defined here (ozz_animation_offline/ispc_texcomp/BunyLib) don't link each
# other via target_link_libraries — cross-library symbol references resolve at AssetPipeline's own
# final link step, the normal way static libraries work.

if(NOT WIN32)
    return()
endif()

# --- ozz_animation_offline ----------------------------------------------------------------------
set(FORGE_OZZ_ROOT "${FORGE_ROOT}/Resources/AnimationSystem/ThirdParty/OpenSource/ozz-animation")
file(GLOB FORGE_OZZ_ANIMATION_OFFLINE_SOURCES "${FORGE_OZZ_ROOT}/src/animation/offline/*.cc")
add_library(ozz_animation_offline STATIC ${FORGE_OZZ_ANIMATION_OFFLINE_SOURCES})
target_link_libraries(ozz_animation_offline PUBLIC Utilities)

# --- BunyLib -----------------------------------------------------------------------------------
# Buny.c, plus lz4hc.c and the full zstd/compress/*.c compiled directly in — neither piece lives in
# Utilities, since lz4hc.c/zstd's compress side are unused by everything else in this template
# (Utilities only needs zstd's decompress side). BunyTool.c (the separate CLI wrapper's own main())
# isn't needed here — AssetPipelineCmd links BunyLib.lib, not a BunyTool executable.
file(GLOB FORGE_BUNYLIB_ZSTD_COMPRESS_SOURCES "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/zstd/compress/*.c")
add_library(BunyLib STATIC
    "${FORGE_ROOT}/Tools/BunyArchive/Buny.c"
    "${FORGE_ROOT}/Utilities/ThirdParty/OpenSource/lz4/lz4hc.c"
    ${FORGE_BUNYLIB_ZSTD_COMPRESS_SOURCES}
)
target_link_libraries(BunyLib PUBLIC Utilities)

# --- ispc_texcomp --------------------------------------------------------------------------------
# kernel.ispc/kernel_astc.ispc each compile to 5 object files (a dispatcher stub plus one per ISA
# target) via the vendored ispc.exe — not C/C++ source ispc_texcomp.cpp compiles itself, so these
# are added as pre-built EXTERNAL_OBJECT sources.
set(FORGE_ISPC_TEXCOMP_ROOT "${FORGE_ROOT}/Tools/ThirdParty/OpenSource/ISPCTextureCompressor")
set(FORGE_ISPC_EXE "${FORGE_ISPC_TEXCOMP_ROOT}/ISPC/win/ispc.exe")
set(FORGE_ISPC_INTDIR "${CMAKE_CURRENT_BINARY_DIR}/ispc_kernels")
file(MAKE_DIRECTORY "${FORGE_ISPC_INTDIR}")

function(forge_add_ispc_kernel out_objects_var kernel_name)
    set(_ispc_src "${FORGE_ISPC_TEXCOMP_ROOT}/ispc_texcomp/${kernel_name}.ispc")
    set(_ispc_header "${FORGE_ISPC_INTDIR}/${kernel_name}_ispc.h")
    set(_ispc_objects
        "${FORGE_ISPC_INTDIR}/${kernel_name}.obj"
        "${FORGE_ISPC_INTDIR}/${kernel_name}_sse2.obj"
        "${FORGE_ISPC_INTDIR}/${kernel_name}_sse4.obj"
        "${FORGE_ISPC_INTDIR}/${kernel_name}_avx.obj"
        "${FORGE_ISPC_INTDIR}/${kernel_name}_avx2.obj"
    )
    add_custom_command(
        OUTPUT ${_ispc_objects} "${_ispc_header}"
        COMMAND "${FORGE_ISPC_EXE}" -O2 "${_ispc_src}"
                -o "${FORGE_ISPC_INTDIR}/${kernel_name}.obj"
                -h "${_ispc_header}"
                --target=sse2,sse4,avx,avx2 --opt=fast-math
        DEPENDS "${_ispc_src}"
        COMMENT "ispc: compiling ${kernel_name}.ispc"
        VERBATIM
    )
    set_source_files_properties(${_ispc_objects} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
    set(${out_objects_var} ${_ispc_objects} PARENT_SCOPE)
endfunction()

forge_add_ispc_kernel(FORGE_ISPC_KERNEL_OBJECTS "kernel")
forge_add_ispc_kernel(FORGE_ISPC_KERNEL_ASTC_OBJECTS "kernel_astc")

add_library(ispc_texcomp STATIC
    "${FORGE_ISPC_TEXCOMP_ROOT}/ispc_texcomp/ispc_texcomp.cpp"
    "${FORGE_ISPC_TEXCOMP_ROOT}/ispc_texcomp/ispc_texcomp_astc.cpp"
    ${FORGE_ISPC_KERNEL_OBJECTS}
    ${FORGE_ISPC_KERNEL_ASTC_OBJECTS}
)
# kernel_ispc.h/kernel_astc_ispc.h are generated into FORGE_ISPC_INTDIR, not reachable via a relative
# #include from ispc_texcomp.cpp the way every other module's headers have been so far — this is the
# one real target_include_directories this whole template has needed.
target_include_directories(ispc_texcomp PRIVATE "${FORGE_ISPC_INTDIR}")

# --- AssetPipeline (the exe itself) -------------------------------------------------------------
file(GLOB FORGE_MESHOPTIMIZER_SOURCES "${FORGE_ROOT}/Tools/ThirdParty/OpenSource/meshoptimizer/src/*.cpp")

add_executable(AssetPipeline
    "${FORGE_ROOT}/Tools/AssetPipeline/src/AssetPipeline.cpp"
    "${FORGE_ROOT}/Tools/AssetPipeline/src/AssetPipelineCmd.cpp"
    "${FORGE_ROOT}/Tools/AssetPipeline/src/AssetPipeline_Textures.cpp"
    "${FORGE_ROOT}/Utilities/FileSystem/ToolFileSystem.c"
    "${FORGE_ROOT}/OS/Windows/WindowsToolsFileSystem.cpp"
    "${FORGE_ROOT}/Resources/AnimationSystem/ThirdParty/OpenSource/TressFX/TressFXAsset.cpp"
    ${FORGE_MESHOPTIMIZER_SOURCES}
)
target_link_libraries(AssetPipeline PRIVATE
    OS
    ozz_base
    ozz_animation
    ozz_animation_offline
    ispc_texcomp
    BunyLib
    winmm
)
# WindowsTime.c's timeGetTime needs WinMM.lib, but the #pragma comment(lib, "WinMM.lib") that would
# normally pull it in lives in WindowsWindow.cpp instead — a static library only pulls in the .obj
# members its link actually references, and AssetPipeline (headless) never references anything from
# WindowsWindow.cpp.obj, so that pragma never fires. Linked explicitly here instead.
