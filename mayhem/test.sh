#!/usr/bin/env bash
#
# mayhem/test.sh — RUN Kuroko's upstream functional test suite (built by
# mayhem/build.sh). Mirrors the upstream `make test` recipe: run the ./kuroko
# interpreter over every test/*.krk and diff stdout against the golden
# test/*.krk.expect file. This asserts BEHAVIOR (golden-output diffs), so a
# sabotage patch that neuters the interpreter to exit(0) fails the diffs.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -x ./kuroko ]; then
  echo "ERROR: ./kuroko not built — mayhem/build.sh must build it first" >&2
  emit_ctrf "kuroko-make-test" 0 1
  exit 1
fi

passed=0
failed=0
for i in test/*.krk; do
  KUROKO_TEST_ENV=1 ./kuroko "$i" > "$i.actual" 2>/dev/null || true
  if diff -q "$i.expect" "$i.actual" >/dev/null 2>&1; then
    passed=$((passed+1))
  else
    failed=$((failed+1))
    echo "FAIL: $i"
    diff "$i.expect" "$i.actual" | head -20 || true
  fi
  rm -f "$i.actual"
done

echo "kuroko test suite: $passed passed, $failed failed"
emit_ctrf "kuroko-make-test" "$passed" "$failed"
