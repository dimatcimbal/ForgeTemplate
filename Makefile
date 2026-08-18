# Thin convenience wrapper around `cmake --preset`/`cmake --build --preset` — CMake + the 8 presets
# in CMakePresets.json remain the real build system; nothing here replaces or bypasses that.
# PRESET/RELEASE_PRESET below are derived generically (dev->prod substitution) so this covers all 8
# presets, not hardcoded to one compiler.
#
# PRESET selects which of the 8 CMakePresets.json presets every target below operates on. Defaulted
# by host OS, not to a single hardcoded name:
#   Windows -> msvc-dev   (real cl.exe: the one toolchain proven to build this vendored tree with
#                          /W4 /WX and zero suppressions — see cmake/forge-toolchain-clang-cl.cmake's
#                          own comments on why clang-cl can't carry the same policy)
#   Linux   -> linux-gcc-dev
# Override per-invocation: `make build PRESET=clang-dev`, `make build PRESET=linux-clang-prod`, ...
ifeq ($(OS),Windows_NT)
    DEFAULT_PRESET := msvc-dev
else
    DEFAULT_PRESET := linux-gcc-dev
endif
PRESET ?= $(DEFAULT_PRESET)

# `release` target's preset: PRESET's own "-dev" suffix swapped for "-prod" by default (msvc-dev ->
# msvc-prod, linux-clang-dev -> linux-clang-prod, ...) rather than hardcoded to one compiler pair —
# generalizes across all 8 presets instead of just one. Override directly if PRESET is already a
# "-prod" preset or doesn't follow the -dev/-prod naming: `make release RELEASE_PRESET=clang-prod`.
RELEASE_PRESET ?= $(patsubst %-dev,%-prod,$(PRESET))

BUILD_DIR   := build-$(PRESET)
RELEASE_DIR := build-$(RELEASE_PRESET)

# Optional: `make build TARGET=01_Transformations` to build a single target instead of everything;
# `make build JOBS=8` to cap parallelism (otherwise ninja's own default, one job per logical core).
TARGET ?=
JOBS   ?=

CMAKE_BUILD_ARGS :=
ifneq ($(TARGET),)
    CMAKE_BUILD_ARGS += --target $(TARGET)
endif
ifneq ($(JOBS),)
    CMAKE_BUILD_ARGS += --parallel $(JOBS)
endif

.PHONY: build release rebuild configure clean clean-all help

# Configure project and drop compile_commands.json into the root — CMAKE_EXPORT_COMPILE_COMMANDS is
# already ON in every preset, but it lands in $(BUILD_DIR) by construction (one per preset, since
# each preset can pick a different compiler entirely); IDE tooling that expects a single root-level
# compile_commands.json needs it copied out explicitly. Already gitignored.
configure:
	cmake --preset $(PRESET)
	cmake -E copy $(BUILD_DIR)/compile_commands.json compile_commands.json
	@echo "DONE: configure ($(PRESET))"

# Build; auto-configures first if the build dir doesn't exist yet.
build: $(BUILD_DIR)/CMakeCache.txt
	cmake --build --preset $(PRESET) $(CMAKE_BUILD_ARGS)
	@echo "DONE: build ($(PRESET))"

# Build with $(RELEASE_PRESET) regardless of PRESET/its dev-vs-prod default.
release: $(RELEASE_DIR)/CMakeCache.txt
	cmake --build --preset $(RELEASE_PRESET) $(CMAKE_BUILD_ARGS)
	@echo "DONE: release ($(RELEASE_PRESET))"

# Single pattern rule (not two separate literal ones keyed off $(BUILD_DIR)/$(RELEASE_DIR)) used by
# both `build` and `release` to skip a redundant configure when already done — deliberate: when
# PRESET is itself already a "-prod" preset (e.g. `make release PRESET=clang-prod`),
# RELEASE_PRESET's dev->prod patsubst leaves it unchanged, so BUILD_DIR and RELEASE_DIR collide on
# the exact same path. Two literal rules for the same target is a duplicate-rule conflict (GNU Make
# silently keeps only the last one, with a "warning: overriding commands for target"); one pattern
# rule sidesteps it instead of just tolerating the warning.
build-%/CMakeCache.txt:
	cmake --preset $*
	cmake -E copy build-$*/compile_commands.json compile_commands.json

rebuild: clean configure
	cmake --build --preset $(PRESET) $(CMAKE_BUILD_ARGS)
	@echo "DONE: rebuild ($(PRESET))"

# Removes $(BUILD_DIR) only (the current PRESET) — never touches any other preset's already-built
# output. `cmake -E rm -rf` rather than a bare `rm -rf` — cmake.exe is already a hard requirement
# everywhere this Makefile runs, whereas `rm` on Windows only exists via Git Bash/MSYS being on PATH,
# an assumption GNU Make itself doesn't guarantee. `cmake -E rm` behaves identically cross-platform
# (recursive + force, silent on a nonexistent path).
clean:
	cmake -E rm -rf $(BUILD_DIR)
	cmake -E rm -f compile_commands.json

# Removes every preset's build directory at once — worth having distinctly from `clean` given this
# template spans 8 presets. $(wildcard build-*) is Make's own glob (evaluated fresh at recipe-run
# time, not stale from Makefile-parse time), passed as a literal, already-expanded list to
# cmake -E rm. Guarded with a shell test because `cmake -E rm -rf` with zero arguments (a fresh
# checkout with no build-* directories yet) errors outright ("Missing file/directory to remove")
# rather than silently no-op'ing.
clean-all:
	@dirs="$(wildcard build-*)"; if [ -n "$$dirs" ]; then cmake -E rm -rf $$dirs; fi
	cmake -E rm -f compile_commands.json

help:
	@echo "Usage: make [target] [PRESET=<preset>] [TARGET=<cmake-target>] [JOBS=<n>]"
	@echo ""
	@echo "Targets:"
	@echo "  configure    Generate project files and copy compile_commands.json to root"
	@echo "  build        Build (auto-configures if needed); TARGET= to build one target"
	@echo "  release      Build with RELEASE_PRESET (default: PRESET with -dev -> -prod)"
	@echo "  rebuild      Clean, configure, and build"
	@echo "  clean        Remove build-\$$(PRESET) and root compile_commands.json"
	@echo "  clean-all    Remove every build-* directory and root compile_commands.json"
	@echo ""
	@echo "Presets (CMakePresets.json, gated by host OS via hostSystemName):"
	@echo "  Windows: clang-dev  clang-prod  msvc-dev  msvc-prod"
	@echo "  Linux:   linux-gcc-dev  linux-gcc-prod  linux-clang-dev  linux-clang-prod"
	@echo ""
	@echo "Default:  PRESET=$(PRESET)  (host-OS-detected; override explicitly to cross this)"
