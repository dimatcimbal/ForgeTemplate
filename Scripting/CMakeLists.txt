# Common_3/Game/Scripting — Forge's Lua-scripting glue (LuaManager/LuaManagerImpl/LuaSystem) plus
# the vendored Lua 5.3.5 interpreter it embeds. Named "Scripting", not "Game" — this target only
# covers Game/Scripting/*, not the rest of Common_3/Game/ (e.g. ThirdParty/OpenSource/flecs, unused),
# and "Game" isn't a real upstream .vcxproj name either (folded into OS.vcxproj upstream, same as
# Application) — naming it after its own actual content matches the precedent Application itself
# already set, rather than upstream's coarser folder grouping.
#
# Not deferred after all: the plan originally guessed "nothing needs Game yet", but that assumed a
# custom bootstrap the way this template's earlier modules were verified — the first *real*,
# unmodified vendored example (Examples/01_Transformations) uses Forge's own
# DEFINE_APPLICATION_MAIN/WindowsMain (OS/Windows/WindowsBase.cpp), which unconditionally calls into
# platformInitLuaScriptingSystem and friends — confirmed directly via a real link failure, not
# assumed.
#
# Depends on Utilities+Application, listed explicitly rather than relying on Application's own
# PUBLIC chain to pull Utilities in transitively — LuaManager/LuaManagerImpl/LuaSystem all call real
# Utilities functions directly (LOGF/etc., confirmed directly), and LuaSystem.cpp genuinely calls
# into Application's IScreenshot/IUI functions (script-exposed screenshot/UI hooks) too, the natural
# direction given scripting sits on top of the UI/rendering layer it scripts against — not the other
# way around. Application's own Profiler/ProfilerBase.cpp calls back into luaRegisterWidget
# (implemented here) — a real, but link-time-only, reverse reference (same "only resolved at the
# final executable's link step, not library-to-library" pattern as OS/AssetPipeline/BunyLib earlier)
# — so this does not need a circular target_link_libraries() edge; whatever executable links both
# Scripting and Application (as every consumer of this template's own established pattern now does
# explicitly) gets both directions resolved at final link.

file(GLOB FORGE_LUA_SOURCES "${FORGE_ROOT}/Game/ThirdParty/OpenSource/lua-5.3.5/src/*.c")
# lua.c/luac.c are the interpreter's own standalone CLI/bytecode-compiler entry points (each defines
# its own main()), not part of the embeddable library — confirmed excluded from the real OS.vcxproj's
# own <ClCompile> list (32 files, not the full 34 in this directory).
list(FILTER FORGE_LUA_SOURCES EXCLUDE REGEX "/luac?\\.c$")

add_library(Scripting STATIC
    "${FORGE_ROOT}/Game/Scripting/LuaManager.cpp"
    "${FORGE_ROOT}/Game/Scripting/LuaManagerImpl.cpp"
    "${FORGE_ROOT}/Game/Scripting/LuaSystem.cpp"
    ${FORGE_LUA_SOURCES}
)
target_link_libraries(Scripting PUBLIC Utilities Application)

if(WIN32)
    # Real, Release-build-only cl.exe /WX false positive on vendored Lua — confirmed directly via a
    # real CI failure, not assumed: lua-5.3.5/src/loslib.c's own checkoption() ends every real code
    # path in a call to luaL_error (a vararg wrapper around longjmp-based error handling, not marked
    # noreturn in any way MSVC's own flow analysis recognizes), so cl.exe's /O2-only control-flow
    # analysis concludes "not all control paths return a value" (C4715) and /WX escalates it to a
    # hard error - only under Release (/O2/NDEBUG), never Debug, which is exactly why this was never
    # caught by this template's own earlier Debug-only build history. A genuine correction to gotcha
    # #2's "cl.exe needs zero suppressions" framing: that held for every module built so far, but
    # Scripting's vendored Lua source is the first real exception, not just a hypothetical one.
    target_compile_options(Scripting PRIVATE /wd4715)
endif()
