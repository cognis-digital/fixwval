#!/usr/bin/env bash
# ============================================================================
# fixwval demos — runnable walkthroughs of the FIX Wire Validator.
# Each demo prints what it does, then runs the tool. The script always exits 0
# (demos are illustrative, not assertions — see tests/run.sh for pass/fail).
# ============================================================================
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

if [ ! -x ./fixwval ]; then
  echo "building fixwval ..."
  cobc -x -free -o fixwval fixwval.cob || { echo "build failed"; exit 0; }
fi
if [ ! -x ./fwmode ]; then
  cobc -x -free -o fwmode fwmode.cob 2>/dev/null || true
fi

rule() { printf '\n========================================================\n'; }

rule
echo "DEMO 1 — validate a clean FIX session log (all PASS)"
echo "\$ fixwval demos/session_clean.fix"
rule
./fixwval demos/session_clean.fix
echo "exit=$?"

rule
echo "DEMO 2 — validate a session with INJECTED errors (reject triage)"
echo "\$ fixwval demos/session_broken.fix"
rule
./fixwval demos/session_broken.fix
echo "exit=$?"

rule
echo "DEMO 3 — CheckSum recompute: same Logon with a corrupted tag 10"
echo "shows declared-vs-expected so you can repair a gateway config"
echo "\$ fixwval demos/checksum_demo.fix"
rule
./fixwval demos/checksum_demo.fix
echo "exit=$?"

rule
echo "DEMO 4 — FIX.4.4 ExecutionReport conformance"
echo "\$ fixwval demos/exec_44.fix"
rule
./fixwval demos/exec_44.fix
echo "exit=$?"

rule
echo "DEMO 5 — real-SOH (0x01) wire capture, auto-detected"
echo "\$ fixwval demos/wire_capture.fix"
rule
./fixwval demos/wire_capture.fix
echo "exit=$?"

rule
echo "DEMO 6 — machine-readable JSONL output for pipelines"
echo "\$ fixwval demos/session_broken.fix --json"
rule
./fixwval demos/session_broken.fix --json
echo "exit=$?"

rule
echo "DEMO 7 — legacy fixed-width numeric-field mode (fwmode)"
echo "\$ fwmode demos/legacy.dat 5 4   (numeric field at col 5, width 4)"
rule
if [ -x ./fwmode ]; then
  ./fwmode demos/legacy.dat 5 4
  echo "exit=$?"
else
  echo "(fwmode not built)"
fi

rule
echo "all demos complete"
exit 0
