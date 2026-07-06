# fixwval — Architecture

`fixwval` is a single GnuCOBOL program (`fixwval.cob`) compiled with
`cobc -x -free`. It reads a file of FIX messages line by line, parses each into
a field table, runs a fixed battery of checks, and reports. There is no dynamic
allocation, no network, and no external dependency beyond the COBOL runtime.

## Data flow

```
   file (LINE SEQUENTIAL)
        │  READ one line = one FIX message
        ▼
   HANDLE-LINE ── skip blank / '#' comment lines
        │
        ├─ PICK-DELIM        choose '|' or SOH (per --soh, else auto-detect)
        ├─ PARSE-FIELDS      split on delimiter → FLD table (tag/value/len)
        │     └─ STORE-TOKEN → CHECK-TAG-NUMERIC
        ├─ VALIDATE-MESSAGE  run the check battery, appending to VIOL table
        └─ REPORT-MESSAGE    human line(s) or JSONL object
        ▼
   EMIT-SUMMARY  →  {"tool":"fixwval","messages":N,"pass":P,"fail":F}
   RETURN-CODE   →  2 if any fail, 0 if all pass, 1 on usage/IO
```

## Parse model

Each line is split on the active delimiter into tokens; each token is split on
its **first** `=` into a tag and a value. Results land in an `OCCURS 512` table:

```cobol
01 FIELD-TABLE.
   05 FLD OCCURS 512 TIMES INDEXED BY FX.
      10 FLD-TAG        PIC X(16).    *> text of the tag
      10 FLD-TAGNUM     PIC 9(6).     *> numeric tag (if all-digits)
      10 FLD-TAGNUM-OK  PIC X.        *> 'Y' if tag is all digits
      10 FLD-VAL        PIC X(1024).
      10 FLD-VLEN       PIC 9(5).
```

A token with no `=`, or a non-numeric tag, is flagged `MALFORMED_FIELD`.

### The shared-index discipline

COBOL `PERFORM VARYING` loops share `WORKING-STORAGE` counters, so a sub-paragraph
that reuses the caller's loop variable will silently corrupt the caller's loop.
The parser therefore uses a **dedicated private set** (`WS-P`, `WS-TS`, `WS-PTOK`,
`WS-PTLEN`, `WS-PEQ`, `WS-PN`, `WS-TN-*`) that no validation paragraph touches.
Validation paragraphs, in turn, drive the table index `FX` and generic scratch
(`WS-I`, `WS-K`) only within their own scope. This separation is the single most
important correctness invariant in the program.

## Validation battery (`VALIDATE-MESSAGE`)

Run in order; each may append to the per-message `VIOL` table and clears
`WS-MSG-OK` on any violation:

1. `CHECK-MALFORMED-FIELDS` — every field is a numeric `tag=value`.
2. `CHECK-HEADER-ORDER` — 8 first, 9 second, 35 third, 10 last.
3. `SET-VERSION-AND-MSGTYPE` — capture BeginString (8) and MsgType (35).
4. `CHECK-BODYLENGTH` — declared tag 9 vs computed body bytes.
5. `CHECK-CHECKSUM` — declared tag 10 vs computed checksum.
6. `CHECK-MSGTYPE-KNOWN` — 35 in the recognized set.
7. `CHECK-SESSION-REQUIRED` — 49/56/34/52 present.
8. `CHECK-REQUIRED-FIELDS` — per-MsgType required tags present.
9. `CHECK-ENUMS` — enumerated tags carry legal values.
10. `CHECK-INT-TYPES` — integer tags are all digits.
11. `CHECK-TIMESTAMPS` — 52/60 are well-formed UTCTimestamps.

## Validation tables

All rule data is encoded as `FILLER`-initialized tables redefined as `OCCURS`
arrays — no code changes needed to extend, just add rows and bump the count:

| Table | Shape | Purpose |
|-------|-------|---------|
| `MT-TABLE` | code → name | MsgType recognition + friendly name |
| `REQ-TABLE` | msgtype → required tag | per-MsgType required fields |
| `SESS-TABLE` | tag | session-level required fields |
| `ENUM-TABLE` | tag → legal value | enumerated-field legal sets |
| `ENUM-TAGS` | tag | which tags are enum-checked at all |
| `INT-TAGS` | tag | integer-typed tags |

## CheckSum algorithm

Per the FIX spec, the checksum is the sum of the byte values of **every character
up to and including the SOH that terminates the field before tag 10**, taken
mod 256, and rendered as a 3-digit zero-padded decimal.

`fixwval` computes this over a **canonical SOH stream** so pipe fixtures and real
captures agree. For each field before tag 10 (`SUM-ONE-FIELD`): sum the tag
characters, add `61` for `=`, sum the value characters, then add `1` for the
terminating SOH byte. `WS-CALC-CS = FUNCTION MOD(WS-SUM, 256)`, then compare to
the declared 3-digit value.

```
CheckSum = ( Σ bytes( "tag=value" + SOH )  for every field before tag 10 ) mod 256
```

Byte values are obtained with `FUNCTION ORD(char) - 1` (GnuCOBOL `ORD` is
1-based), giving the true ASCII code.

## BodyLength algorithm

BodyLength (tag 9) is the number of bytes from the first byte after the SOH that
terminates `9=<val>`, up to and including the SOH that terminates the field
immediately before tag 10.

Rather than hunting byte offsets in a delimiter-specific buffer, `fixwval`
reconstructs a canonical offset for each field (`COMPUTE-FIELD-OFFSETS`): each
field contributes `len(tag) + 1 (for '=') + len(value) + 1 (for SOH)` bytes.
The body starts one byte after tag 9's field and ends at the SOH just before
tag 10. `WS-BODYLEN-CALC = WS-BL-END - WS-BL-START + 1`, compared to the declared
value. This makes the check identical for pipe- and SOH-delimited input.

## Reporting

- Human mode: one `msg N PASS/FAIL ...` line, followed by `- [CODE] detail`
  lines for failures.
- `--json` mode: one JSON object per message (`REPORT-MESSAGE-JSON`), with
  `EMIT-VIOL-DETAIL` escaping `"` and `\` so the detail string is valid JSON.
- Always: a final summary object and a process exit code.

## Programs in the repo

| File | Role |
|------|------|
| `fixwval.cob` | The FIX Wire Validator (flagship). |
| `fwmode.cob` | Legacy fixed-width numeric-field validator (secondary mode). |

## Portability notes

- Compiled with `cobc -x -free` (free-format source, standalone executable).
- Uses only standard intrinsic functions (`TRIM`, `LENGTH`, `NUMVAL`, `ORD`,
  `MOD`, `CHAR`, `UPPER-CASE`) available in GnuCOBOL 3.x.
- `ACCEPT ... FROM ARGUMENT-VALUE` for CLI args; `ORGANIZATION LINE SEQUENTIAL`
  for input — both portable across GnuCOBOL platforms.
- No vendor extensions, EBCDIC assumptions, or platform-specific file handling.
  SOH is obtained portably via `FUNCTION CHAR(2)` (the 2nd collating position =
  code point 1 = SOH).
