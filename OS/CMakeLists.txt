# Common_3/OS — the platform layer: window creation/input, the platform Log/Thread/Time/FileSystem
# backends, and the platform-specific hidapi/cpu_features third-party sources.
#
# One CMake target name, not a separate top-level directory per platform — if(WIN32)/if(UNIX)
# branching stays inside this one file.
#
# GTK (<gtk/gtk.h>, Linux native dialogs) is the one exception to the relative-path include
# convention — no vendored copy in ForgeSrc, so it needs a real include path via pkg_check_modules()
# below.

if(WIN32)
    file(GLOB FORGE_OS_SOURCES
        "${FORGE_ROOT}/OS/Windows/*.c"
        "${FORGE_ROOT}/OS/Windows/*.cpp"
        "${FORGE_ROOT}/OS/ThirdParty/OpenSource/hidapi/windows/*.c"
    )
    # WindowsToolsFileSystem.cpp is AssetPipeline's Tools/FileSystem add-on, not OS's own platform
    # layer (mirrors ToolFileSystem.c being excluded from Utilities for the same reason) — built by
    # AssetPipeline/CMakeLists.txt instead.
    list(FILTER FORGE_OS_SOURCES EXCLUDE REGEX "WindowsToolsFileSystem\\.cpp$")
    list(APPEND FORGE_OS_SOURCES
        "${FORGE_ROOT}/OS/ThirdParty/OpenSource/cpu_features/src/impl_x86_windows.c"
    )
elseif(UNIX)
    file(GLOB FORGE_OS_SOURCES
        "${FORGE_ROOT}/OS/Linux/*.c"
        "${FORGE_ROOT}/OS/Linux/*.cpp"
        "${FORGE_ROOT}/OS/ThirdParty/OpenSource/hidapi/linux/*.c"
    )
    # LinuxToolsFileSystem.c — same AssetPipeline-only exclusion as WindowsToolsFileSystem.cpp above.
    list(FILTER FORGE_OS_SOURCES EXCLUDE REGEX "LinuxToolsFileSystem\\.c$")
    list(APPEND FORGE_OS_SOURCES
        "${FORGE_ROOT}/OS/ThirdParty/OpenSource/cpu_features/src/impl_x86_linux_or_android.c"
    )
endif()

list(APPEND FORGE_OS_SOURCES
    "${FORGE_ROOT}/OS/WindowSystem/WindowSystem.cpp"
    "${FORGE_ROOT}/OS/CPUConfig.cpp"
)

add_library(OS STATIC ${FORGE_OS_SOURCES})
target_link_libraries(OS PUBLIC Utilities)

if(UNIX)
    # GTK/X11/Xrandr/libudev — the exact set upstream's own OSBase.project links. PUBLIC, not
    # PRIVATE: OS is a static library, so these are usage requirements that only actually get linked
    # into whatever executable eventually links OS.
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(FORGE_OS_GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)
    pkg_check_modules(FORGE_OS_X11 REQUIRED IMPORTED_TARGET x11)
    pkg_check_modules(FORGE_OS_XRANDR REQUIRED IMPORTED_TARGET xrandr)
    target_link_libraries(OS PUBLIC
        PkgConfig::FORGE_OS_GTK3
        PkgConfig::FORGE_OS_X11
        PkgConfig::FORGE_OS_XRANDR
        udev
        dl
        pthread
    )
endif()
