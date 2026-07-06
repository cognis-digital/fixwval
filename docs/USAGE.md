# fixwval — Usage

## Synopsis

```
fixwval <file> [--soh PIPE|SOH|AUTO] [--json]
```

`fixwval` reads a file of FIX messages, **one message per line**, validates each,
and writes a report to stdout. It never opens a socket or modifies input.

## Arguments

| Argument | Meaning |
|----------|---------|
| `<file>` | Path to a file of FIX messages, one per line. Blank lines and lines beginning with `#` are skipped. |
| `--soh PIPE` | Field delimiter is the pipe character `\|` (human-readable fixtures). |
| `--soh SOH` | Field delimiter is the ASCII SOH byte `0x01` (raw wire capture). |
| `--soh AUTO` | Detect per line: SOH if a `0x01` is present, else pipe. **Default.** |
| `--json` | Emit machine-readable JSONL (one object per message) plus a summary object; suppress the human report. |

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Every message passed. |
| `2` | At least one message failed validation. |
| `1` | Usage error (no file given) or I/O error (file cannot be opened). |

The exit code is designed for pipeline gating — a non-zero exit means "stop the batch."

## Output

### Human report (default)

```
fixwval — FIX Wire Validator
file: demos/session_clean.fix
----------------------------------------
msg 1 PASS  35=A (Logon)  FIX.4.2
msg 2 PASS  35=D (NewOrderSingle)  FIX.4.2
----------------------------------------
{"tool":"fixwval","messages":2,"pass":2,"fail":0}
```

Each message line shows its 1-based index, PASS/FAIL, the `MsgType` (with a
friendly name when recognized), and the `BeginString` version. Failures list
each violation as `[CODE] detail`.

### JSON mode (`--json`)

One JSON object per message (JSONL), followed by the summary object. Suitable
for piping into `jq`, a log shipper, or a conformance dashboard:

```
{"msg":1,"msgtype":"A","version":"FIX.4.2","status":"PASS","violations":[]}
{"msg":2,"msgtype":"D","version":"FIX.4.2","status":"FAIL","violations":[{"code":"MISSING_REQUIRED","detail":"msgtype D requires tag 60"}]}
{"tool":"fixwval","messages":2,"pass":1,"fail":1}
```

## Violation codes

| Code | When it fires |
|------|---------------|
| `MALFORMED_FIELD` | A field is not a numeric `tag=value` pair. |
| `HEADER_ORDER` | Tag 8/9/35 not in the required first/second/third position. |
| `TRAILER_ORDER` | Tag 10 (CheckSum) is not the last field. |
| `BAD_BODYLENGTH` | Declared tag 9 ≠ computed body byte count (shows declared/actual). |
| `BAD_CHECKSUM` | Declared tag 10 ≠ computed checksum mod 256 (shows declared/expected). |
| `BAD_CHECKSUM_FMT` | Tag 10 is not exactly 3 digits. |
| `UNKNOWN_MSGTYPE` | Tag 35 value not in the recognized MsgType set. |
| `MISSING_REQUIRED` | A session-level or per-MsgType required tag is absent. |
| `BAD_ENUM` | A field with a known enumeration carries a value outside its legal set. |
| `BAD_INT` | An integer-typed tag (e.g. 9, 34, 98, 108) is non-numeric. |
| `BAD_TIMESTAMP` | Tag 52 or 60 is not a well-formed `YYYYMMDD-HH:MM:SS[.sss]`. |
| `EMPTY_MESSAGE` | A line had no parseable fields. |

See [FIX_RULES.md](FIX_RULES.md) for the exact tags and versions covered.

## Recipes

**Gate a CI job on a captured session:**

```bash
fixwval captured_session.fix || { echo "FIX session invalid"; exit 1; }
```

**Count failures with jq:**

```bash
fixwval session.fix --json | jq -s '[.[] | select(.status=="FAIL")] | length'
```

**Extract just the reject reasons:**

```bash
fixwval session.fix --json \
  | jq -r 'select(.violations) | .violations[] | "\(.code)\t\(.detail)"'
```

**Validate a raw tcpdump-style capture (real SOH):**

```bash
fixwval wire_capture.fix --soh SOH
```

**Legacy fixed-width (non-FIX) records:**

```bash
fwmode positional_records.dat 5 4    # numeric field at column 5, width 4
```
