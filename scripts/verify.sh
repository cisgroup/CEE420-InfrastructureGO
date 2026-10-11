#!/usr/bin/env bash
# Every local check in one run. The whole output is kept in build/verify-<date>.txt and the run ends with one line
# per check, so that a report can quote a file and not a memory. A check that does not exist yet on this machine is
# named as skipped with its reason and never counted as held.
set -u
cd "$(dirname "$0")/.."
mkdir -p build
out="build/verify-$(date +%Y-%m-%d).txt"
: > "$out"
names=()
codes=()

run() {
  local name="$1"
  shift
  echo "== $name, running $*" | tee -a "$out"
  "$@" 2>&1 | tee -a "$out"
  local code=${PIPESTATUS[0]}
  names+=("$name")
  codes+=("$code")
}

skip() {
  echo "== $1, skipped because $2" | tee -a "$out"
  names+=("$1")
  codes+=("skipped")
}

run "derived files" uv run python -m igo.inlets --check
run "fact cards" uv run python -m igo.facts --check
run "game data and cases" uv run python -m igo.game
run "pipeline tests" uv run pytest -rs
if [ -f app/Package.swift ]; then
  run "game rules in swift" swift test --package-path app
else
  skip "game rules in swift" "app/Package.swift does not exist yet"
fi
if [ -d app/InfrastructureGO.xcodeproj ] && xcrun simctl list runtimes 2>/dev/null | grep -q "iOS"; then
  run "app tests in the simulator" app/scripts/test.sh
else
  skip "app tests in the simulator" "the Xcode project or an iPhone simulator is missing"
fi
if [ -d web/tests ]; then
  run "web logic" node --test web/tests
else
  skip "web logic" "web/tests does not exist yet"
fi
if command -v supabase >/dev/null 2>&1 && [ -d backend/supabase/tests ]; then
  run "backend rules" supabase --workdir backend test db
else
  skip "backend rules" "the Supabase CLI or backend/supabase/tests is missing"
fi

echo | tee -a "$out"
echo "== summary of $(git rev-parse --short HEAD 2>/dev/null || echo 'no commit') on $(date +%Y-%m-%d)" | tee -a "$out"
failed=0
for k in "${!names[@]}"; do
  case "${codes[$k]}" in
    0) verdict="held" ;;
    skipped) verdict="skipped" ;;
    *) verdict="did not hold, exit code ${codes[$k]}"; failed=1 ;;
  esac
  printf '   %-22s %s\n' "${names[$k]}" "$verdict" | tee -a "$out"
done
echo "the full output is in $out"
exit $failed
