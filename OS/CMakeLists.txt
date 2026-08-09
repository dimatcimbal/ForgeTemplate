# Common_3/OS — the platform layer: window creation/input, the platform Log/Thread/Time/FileSystem
# backends, and the platform-specific hidapi/cpu_features third-party sources. First module where
# the source list genuinely diverges per platform (Utilities only diverges by one file).
#
# One CMake target name, not a separate top-level directory per platform — matches CMake's own
# idiom (if(WIN32)/if(UNIX) branching inside one target's own CMakeLists.txt) rather than the
# vcxproj-forced pattern of a separate project per platform, see plan/module-split.md's "One target
# name per module" section.
#
# As with Utilities, every header here is reached via paths relative to the including file itself
# (confirmed: impl_x86_windows.c's "cpu_features_macros.h" and hid.c's "../hidapi.h" both resolve
# purely from their own directory, no include path needed) — with one real exception: Linux's
# LinuxBase.cpp/LinuxWindow.cpp use GTK (<gtk/gtk.h>) for native dialogs, a real system library with
# no vendored copy in ForgeSrc, so it does need a proper include path — see the pkg_check_modules()
# block below, matching upstream's own SteamOS_CodeLite/OSBase.project exactly (its Compiler Options
# already run "$(shell pkg-config --cflags gtk+-3.0)", confirmed directly).

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
    # GTK (native dialogs), X11 + Xrandr (window/display-mode management), libudev (joystick/gamepad
    # hotplug detection via LinuxInput.cpp) — the exact set upstream's own OSBase.project links
    # ("-ludev;-ldl;-pthread;-lXrandr;$(shell pkg-config --libs gtk+-3.0)" plus a bundled libX11.a;
    # this template uses the system libX11 via pkg-config instead of vendoring one). PUBLIC, not
    # PRIVATE — OS is a static library, so these are usage requirements that only actually get linked
    # into whatever executable eventually links OS, not into OS.a itself.
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
