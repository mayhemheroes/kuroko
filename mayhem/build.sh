#!/usr/bin/env bash
#
# mayhem/build.sh — build the Kuroko fuzz harness + standalone reproducer + the
# project's own build (used by the upstream `make test` functional suite).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# Relax ONLY the UBSan pointer-overflow check: krk_resetStack() does
# `stack + stackSize` on the very first krk_initVM() when stack==NULL/size==0
# ("applying zero offset to null pointer"), a benign pattern that fires on
# EVERY interpreter startup — so every fuzz input would abort immediately. ASan
# and the rest of UBSan stay on and halting.
SANITIZER_FLAGS="$SANITIZER_FLAGS -fno-sanitize=pointer-overflow"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# ---------------------------------------------------------------------------
# 1) Build the instrumented static library (all interpreter objects, sanitized +
#    coverage-instrumented for libFuzzer). Everything except src/kuroko.c (the
#    CLI main) goes into libkuroko.a via the project's own build rules; we just
#    override CC/CFLAGS so the FUZZED CODE carries ASan/UBSan + edge coverage +
#    DWARF<4.  -fsanitize=fuzzer-no-link instruments without pulling in a main.
# NB: pass CFLAGS through the ENVIRONMENT, not as a `make VAR=` argument — a
# command-line assignment would freeze CFLAGS and suppress the Makefile's
# `CFLAGS += -Isrc -pthread`, breaking the <kuroko/...> includes. As an env var
# the Makefile's `?=` keeps our value and `+=` still appends its own flags.
KRK_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -O1"
CFLAGS="$KRK_CFLAGS" make -j"$MAYHEM_JOBS" libkuroko.a CC="$CC"

# ---------------------------------------------------------------------------
# 2) Compile the harness TWICE: once as the libFuzzer target, once as a
#    standalone (run-once) reproducer against $STANDALONE_FUZZ_MAIN.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
	mayhem/fuzz_kuroko.c -Isrc libkuroko.a -lm -lpthread -ldl \
	-o /mayhem/fuzz_kuroko

$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" \
	mayhem/fuzz_kuroko.c -Isrc libkuroko.a -lm -lpthread -ldl \
	-o /mayhem/fuzz_kuroko-standalone

# ---------------------------------------------------------------------------
# 3) Build the project with its NORMAL flags for the functional test suite
#    (upstream `make test` runs the ./kuroko binary over test/*.krk and diffs
#    against golden .expect files). A clean, separate, uninstrumented build so
#    test.sh only has to RUN it.
# Build single-threaded: the codec-generation step (GENMODS) runs ./kuroko and
# imports the freshly-built module .so's, which races the module builds under
# parallel make (upstream ships their CI as a single-threaded build for exactly
# this reason).
make clean >/dev/null 2>&1 || true
if [ -n "${COVERAGE_FLAGS}" ]; then
	CFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" make -j1 CC="$CC"
else
	env -u CFLAGS make -j1 CC="$CC"
fi
