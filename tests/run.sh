#!/usr/bin/env bash
# ============================================================================
# fixwval test harness — compiles the validator and asserts behavior against
# labeled FIX fixtures. No COBOL unit framework is required: each case runs
# the binary, checks the exit code, and greps for expected violation codes.
#
#   Exit 0  = all assertions passed
#   Exit 1  = one or more assertions failed
#
# Usage:  bash tests/run.sh
# ============================================================================
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

BIN=./fixwval
FX=tests/fixtures
PASS=0
FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# ---- build --------------------------------------------------------------
say "== build =="
if command -v cobc >/dev/null 2>&1; then
  cobc -x -free -o fixwval fixwval.cob \
    && cobc -x -free -o fwmode fwmode.cob \
    || { say "COMPILE FAILED"; exit 1; }
  say "  compiled fixwval + fwmode"
else
  say "cobc not found on PATH — install GnuCOBOL first"; exit 1
fi

# ---- helpers ------------------------------------------------------------
# assert_exit <label> <file> <expected-exit> [extra fixwval args...]
assert_exit() {
  local label="$1" file="$2" want="$3"; shift 3
  "$BIN" "$FX/$file" "$@" >/tmp/out.$$ 2>/tmp/err.$$
  local got=$?
  if [ "$got" = "$want" ]; then ok "$label (exit $got)"
  else bad "$label (exit=$got want=$want)"; sed 's/^/      /' /tmp/out.$$; fi
}

# assert_grep <label> <file> <expected-exit> <pattern> [extra args...]
assert_grep() {
  local label="$1" file="$2" want="$3" pat="$4"; shift 4
  "$BIN" "$FX/$file" "$@" >/tmp/out.$$ 2>/tmp/err.$$
  local got=$?
  local okc=0
  [ "$got" = "$want" ] || okc=1
  grep -q "$pat" /tmp/out.$$ || okc=1
  if [ "$okc" = 0 ]; then ok "$label"
  else bad "$label (exit=$got want=$want pat='$pat')"; sed 's/^/      /' /tmp/out.$$; fi
}

say "== FIX validation cases =="

# valid messages -> exit 0
assert_exit "valid Logon 4.2"           valid_logon.fix        0
assert_exit "valid NewOrderSingle 4.2"  valid_nos.fix          0
assert_exit "valid ExecutionReport 4.4" valid_exec_44.fix      0
assert_exit "valid Logon FIXT.1.1 (5.0)" valid_logon_50.fix    0
assert_exit "valid good session (3 msg)" good_session.fix      0
assert_exit "valid raw-SOH capture"     valid_raw_soh.fix      0

# checksum / bodylength
assert_grep "bad checksum reported"     bad_checksum.fix       2 "BAD_CHECKSUM"
assert_grep "bad checksum expected val" bad_checksum.fix       2 "expected=175"
assert_grep "bad bodylength reported"   bad_bodylength.fix     2 "BAD_BODYLENGTH"
assert_grep "bad bodylength actual val" bad_bodylength.fix     2 "actual=63"

# structural / semantic
assert_grep "header out of order"       header_out_of_order.fix 2 "HEADER_ORDER"
assert_grep "unknown msgtype"           unknown_msgtype.fix    2 "UNKNOWN_MSGTYPE"
assert_grep "missing required field"    missing_required.fix   2 "MISSING_REQUIRED"
assert_grep "missing required is 108"   missing_required.fix   2 "requires tag 108"
assert_grep "bad enum value"            bad_enum.fix           2 "BAD_ENUM"
assert_grep "malformed field"           malformed_field.fix    2 "MALFORMED_FIELD"
assert_grep "bad timestamp"             bad_timestamp.fix      2 "BAD_TIMESTAMP"

# empty input -> no messages, all pass, exit 0
assert_grep "empty file 0 messages"     empty.fix              0 '"messages":0'

# JSON mode
assert_grep "json mode pass object"     good_session.fix       0 '"status":"PASS"' --json
assert_grep "json mode summary"         good_session.fix       0 '"tool":"fixwval"' --json
assert_grep "json mode fail object"     bad_enum.fix           2 '"status":"FAIL"' --json

# explicit --soh flags
assert_exit "explicit --soh PIPE"       valid_logon.fix        0 --soh PIPE
assert_exit "explicit --soh SOH raw"    valid_raw_soh.fix      0 --soh SOH
assert_exit "explicit --soh AUTO"       valid_logon.fix        0 --soh AUTO

say "== 4.2 vs 4.4 difference =="
# ExecutionReport 4.4 is valid; feed it labeled as-is (version echoed in report)
assert_grep "4.4 version echoed"        valid_exec_44.fix      0 "FIX.4.4"
assert_grep "4.2 version echoed"        valid_logon.fix        0 "FIX.4.2"

# ---- legacy fixed-width mode (fwmode) -----------------------------------
say "== legacy fixed-width mode (fwmode) =="
./fwmode tests/fixtures/legacy_fixed.dat 5 4 >/tmp/out.$$ 2>&1
lg=$?
if [ "$lg" = "2" ] && grep -q '"bad":1' /tmp/out.$$; then
  ok "fwmode flags 1 bad record (exit 2)"
else
  bad "fwmode legacy check (exit=$lg)"; sed 's/^/      /' /tmp/out.$$
fi

# ---- usage / IO errors --------------------------------------------------
say "== usage / IO =="
"$BIN" >/dev/null 2>&1; [ $? = 1 ] && ok "no-arg usage exit 1" || bad "no-arg usage"
"$BIN" tests/fixtures/does_not_exist.fix >/dev/null 2>&1
[ $? = 1 ] && ok "missing file exit 1" || bad "missing file exit"

rm -f /tmp/out.$$ /tmp/err.$$
say ""
say "== results: $PASS passed, $FAIL failed =="
[ "$FAIL" = 0 ] || exit 1
