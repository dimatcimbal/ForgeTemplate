# Resources/AnimationSystem/ThirdParty/OpenSource/ozz-animation — ozz-animation's base + runtime
# modules only (ozz_base, ozz_animation), matching upstream's own separate ozz_base.vcxproj/
# ozz_animation.vcxproj. ozz_animation_offline stays defined inside AssetPipeline/CMakeLists.txt —
# it's the only real consumer (offline content baking), and pulling it in here would mean every
# consumer of this module (including runtime-only ones like Animation/Examples/*) has to build it
# too, for a module they never call into.
#
# Cross-platform, unlike AssetPipeline (Windows-only) — real upstream examples that need
# ozz_base/ozz_animation at runtime (06_MaterialPlayground, 21_Animations, 28_Skinning) are not
# Windows-only in SteamOS_CodeLite, so this module can't be gated the same way AssetPipeline is.

set(FORGE_OZZ_ROOT "${FORGE_ROOT}/Resources/AnimationSystem/ThirdParty/OpenSource/ozz-animation")

# Explicit file list, not a directory glob — matches ozz_base.vcxproj's own curated list, not
# everything under src/base/.
add_library(ozz_base STATIC
    "${FORGE_OZZ_ROOT}/src/base/memory/allocator.cc"
    "${FORGE_OZZ_ROOT}/src/base/platform.cc"
    "${FORGE_OZZ_ROOT}/src/base/containers/string_archive.cc"
    "${FORGE_OZZ_ROOT}/src/base/io/archive.cc"
    "${FORGE_OZZ_ROOT}/src/base/maths/math_archive.cc"
    "${FORGE_OZZ_ROOT}/src/base/maths/soa_math_archive.cc"
    "${FORGE_OZZ_ROOT}/src/base/maths/simd_math_archive.cc"
)
target_link_libraries(ozz_base PUBLIC Utilities)

file(GLOB FORGE_OZZ_ANIMATION_SOURCES "${FORGE_OZZ_ROOT}/src/animation/runtime/*.cc")
add_library(ozz_animation STATIC ${FORGE_OZZ_ANIMATION_SOURCES})
target_link_libraries(ozz_animation PUBLIC Utilities)
