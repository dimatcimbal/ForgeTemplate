# Resources/AnimationSystem/Animation — Forge's own runtime animation layer built on top of ozz
# (AnimatedObject/Animation/Clip/ClipController/ClipMask/Rig/SkeletonBatcher). Upstream has no
# separate project for this at all — Libraries/OS/OS.vcxproj compiles these files (and
# Application/CameraController.cpp) directly into OS.lib. Split out here because the real
# dependency set doesn't match either OS or Application alone: SkeletonBatcher.cpp creates its own
# GPU pipelines/buffers via Graphics/FSL (needs Renderer), and SkeletonBatcher.h's own
# CameraMatrix mProjectView member needs Application/CameraController.cpp's CameraMatrix
# constructor (not inline, a real link dependency, not just an unused include).
#
# Cross-platform — real upstream examples needing this (06_MaterialPlayground, 21_Animations,
# 28_Skinning) aren't Windows-only.

file(GLOB FORGE_ANIMATION_SOURCES "${FORGE_ROOT}/Resources/AnimationSystem/Animation/*.cpp")

add_library(Animation STATIC ${FORGE_ANIMATION_SOURCES})
target_link_libraries(Animation PUBLIC Utilities ozz_base ozz_animation Renderer Application)
