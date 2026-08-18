# Common_3/Game/Scripting — Forge's Lua-scripting glue (LuaManager/LuaManagerImpl/LuaSystem) plus
# the vendored Lua 5.3.5 interpreter it embeds. Named "Scripting", not "Game" — only covers
# Game/Scripting/*, not the rest of Common_3/Game/ (e.g. the unused flecs).
#
# WindowsMain (OS/Windows/WindowsBase.cpp, via DEFINE_APPLICATION_MAIN) unconditionally calls into
# platformInitLuaScriptingSystem — any example using Forge's own app framework needs this module.
#
# Depends on Utilities+Application, listed explicitly — LuaSystem.cpp also calls directly into
# Application's IScreenshot/IUI functions. Application's own Profiler/ProfilerBase.cpp calls back
# into luaRegisterWidget (implemented here) — a reverse reference, but link-time-only (resolved at
# the final executable's link step, not library-to-library), so no circular target_link_libraries()
# edge is needed.

file(GLOB FORGE_LUA_SOURCES "${FORGE_ROOT}/Game/ThirdParty/OpenSource/lua-5.3.5/src/*.c")
# lua.c/luac.c are the interpreter's own standalone CLI/bytecode-compiler entry points (each defines
# its own main()), not part of the embeddable library.
list(FILTER FORGE_LUA_SOURCES EXCLUDE REGEX "/luac?\\.c$")

add_library(Scripting STATIC
    "${FORGE_ROOT}/Game/Scripting/LuaManager.cpp"
    "${FORGE_ROOT}/Game/Scripting/LuaManagerImpl.cpp"
    "${FORGE_ROOT}/Game/Scripting/LuaSystem.cpp"
    ${FORGE_LUA_SOURCES}
)
target_link_libraries(Scripting PUBLIC Utilities Application)

if(WIN32)
    # Release-build-only cl.exe /WX false positive on vendored Lua: loslib.c's own checkoption() ends
    # every code path in a call to luaL_error (a vararg longjmp-based error wrapper, not marked
    # noreturn), so cl.exe's /O2-only control-flow analysis concludes "not all control paths return a
    # value" (C4715) and /WX escalates it to a hard error — only under Release (/O2/NDEBUG), never
    # Debug.
    target_compile_options(Scripting PRIVATE /wd4715)
endif()
