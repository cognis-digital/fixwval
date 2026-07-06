# fixwval — FIX Wire Validator

**COBOL (GnuCOBOL)** — validates **FIX** (Financial Information eXchange) protocol messages: field structure, mandatory header order, `BodyLength` (tag 9), `CheckSum` (tag 10), `MsgType` (tag 35), per-MsgType required fields, enum values, and data-type/timestamp checks. FIX.4.2 / FIX.4.4 / FIXT.1.1 (5.0).

[![ci](https://github.com/cognis-digital/fixwval/actions/workflows/ci.yml/badge.svg)](https://github.com/cognis-digital/fixwval/actions/workflows/ci.yml)
![lang](https://img.shields.io/badge/lang-COBOL-informational)
![license](https://img.shields.io/badge/license-COCL%201.0-2ea043)

Part of the **[Cognis Neural Suite](https://github.com/cognis-digital)**. Single-purpose, emits machine-readable JSON, exits non-zero when it finds something (CI-friendly).

---

## Why validate FIX on the wire?

FIX is the tag=value protocol that carries the world's equities, futures, and FX order flow between buy-side, sell-side, and exchanges. It is delimited by the ASCII **SOH** byte (`0x01`), self-describing, and unforgiving: a wrong `BodyLength`, a checksum that is off by one byte, a `MsgType` your counterparty doesn't support, or a missing required tag will get the message **rejected at the session layer** — often with a terse reason code that lands in a batch log at 3 a.m.

`fixwval` exists for the moments where you need a small, dependency-free, auditable checker:

- **Pre-trade gateway sanity** — confirm your engine emits structurally-valid FIX before it hits the counterparty.
- **Reject-reason triage** — feed a captured message and get the exact violation (bad checksum with expected-vs-actual, missing required tag, out-of-order header) instead of guessing.
- **Conformance testing** — assert that fixtures for each `MsgType` carry their required fields and legal enum values across FIX versions.
- **Mainframe batch** — parse hostile/garbled captures in a COBOL batch job on the same box that already runs your settlement code. No JVM, no Python, no network.

It is a **validator**, not an order router: it never executes, sends, or acknowledges anything. It reads a file and reports.

---

## Example output

Real output from `fixwval demos/session_broken.fix` (a session with three injected errors):

```
fixwval — FIX Wire Validator
file: demos/session_broken.fix
----------------------------------------
msg 1 PASS  35=A (Logon)  FIX.4.2
msg 2 FAIL  35=A  FIX.4.2
    - [BAD_CHECKSUM] tag 10 declared=000 expected=159
msg 3 FAIL  35=D  FIX.4.2
    - [MISSING_REQUIRED] msgtype D requires tag 60
msg 4 FAIL  35=D  FIX.4.2
    - [BAD_ENUM] tag 40 value 'Z' not a valid enum
----------------------------------------
{"tool":"fixwval","messages":4,"pass":1,"fail":3}
```

Exit code is **2** (at least one message failed). The same run with `--json` emits one object per message (JSONL) plus the summary:

```
{"msg":1,"msgtype":"A","version":"FIX.4.2","status":"PASS","violations":[]}
{"msg":2,"msgtype":"A","version":"FIX.4.2","status":"FAIL","violations":[{"code":"BAD_CHECKSUM","detail":"tag 10 declared=000 expected=159"}]}
{"msg":3,"msgtype":"D","version":"FIX.4.2","status":"FAIL","violations":[{"code":"MISSING_REQUIRED","detail":"msgtype D requires tag 60"}]}
{"msg":4,"msgtype":"D","version":"FIX.4.2","status":"FAIL","violations":[{"code":"BAD_ENUM","detail":"tag 40 value 'Z' not a valid enum"}]}
{"tool":"fixwval","messages":4,"pass":1,"fail":3}
```

---

## Input formats

A FIX message on the wire uses the SOH byte (`0x01`) between fields. `fixwval` reads **one message per line** and accepts either:

- **Real SOH** captures (`0x01` delimiters) — from a tap, log, or replay.
- **Pipe-delimited** fixtures (`|`) — human-readable, diffable, checked into git.

By default (`--soh AUTO`) it detects per line: if a `0x01` is present it uses SOH, otherwise `|`. Force it with `--soh SOH` or `--soh PIPE`. Lines beginning with `#` are treated as comments and skipped.

Pipe-delimited example (a valid Logon):

```
8=FIX.4.2|9=63|35=A|49=CLIENT|56=BROKER|34=1|52=20260706-13:20:00|98=0|108=30|10=175|
```

---

## Build / run

Requires **GnuCOBOL 3.x** (`cobc`). See [Install](#install) for platform steps.

```bash
cobc -x -free -o fixwval fixwval.cob
./fixwval demos/session_clean.fix
```

## Usage

```
fixwval <file> [--soh PIPE|SOH|AUTO] [--json]
  <file>       file of FIX messages, one per line
  --soh PIPE   field delimiter is '|' (human-readable fixtures)
  --soh SOH    field delimiter is ASCII 0x01 (wire capture)
  --soh AUTO   detect per line (default)
  --json       machine-readable JSONL per message + summary (no human report)
```

**Exit codes:** `0` all messages pass · `2` one or more messages fail · `1` usage / I/O error. Gate your CI or pipeline on the exit code.

### Legacy fixed-width mode

The original generic fixed-width numeric-field validator is retained as `fwmode` — useful for positional (non-FIX) COBOL copybook records:

```bash
cobc -x -free -o fwmode fwmode.cob
./fwmode records.dat 5 4      # numeric field at column 5, width 4
# {"tool":"fwmode","records":3,"ok":2,"bad":1,"field_start":5,"field_len":4}
```

---

## Install

**Linux / macOS** — one-liner (installs GnuCOBOL via apt/brew, builds, copies binary):

```bash
./install.sh              # add PREFIX=$HOME/.local to install without sudo
```

**Windows** — GnuCOBOL via MSYS2, Chocolatey, or WSL, then build:

```powershell
./install.ps1             # prints options and builds if cobc is present
```

**Make** (any platform with cobc):

```bash
make          # build fixwval + fwmode
make test     # compile + run tests/run.sh
make demo     # run demos/run_all.sh
make clean
```

**Docker** — no local COBOL toolchain needed:

```bash
docker build -t fixwval .
docker run --rm -v "$PWD:/data" fixwval /data/session.fix
```

Manual install by platform:

| Platform | Get GnuCOBOL | Then |
|----------|--------------|------|
| Debian/Ubuntu | `sudo apt-get install gnucobol` | `cobc -x -free -o fixwval fixwval.cob` |
| macOS (Homebrew) | `brew install gnu-cobol` | `cobc -x -free -o fixwval fixwval.cob` |
| Windows (MSYS2) | `pacman -S mingw-w64-x86_64-gnucobol` | `cobc -x -free -o fixwval fixwval.cob` |
| Windows (Choco) | `choco install gnucobol` | same |
| Windows (WSL) | use the Ubuntu steps inside WSL | same |

---

## Documentation

- **[docs/USAGE.md](docs/USAGE.md)** — CLI, input formats, exit codes, piping to `jq`, integration recipes.
- **[docs/FIX_RULES.md](docs/FIX_RULES.md)** — exactly which tags, rules, versions, and enums are covered — and, honestly, what is **not** yet covered.
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — parse model, validation tables, checksum/bodylength algorithms, COBOL program structure.

## Tests & demos

- `bash tests/run.sh` — compiles both programs and runs 29 labeled assertions (valid Logon/NOS/ExecReport, bad checksum, bad bodylength, missing required, header out of order, unknown msgtype, bad enum, malformed field, bad timestamp, empty file, 4.2 vs 4.4, JSON mode, `--soh` flags, legacy mode, usage/IO).
- `bash demos/run_all.sh` — 7 runnable walkthroughs.

Both run in CI on every push/PR (see [.github/workflows/ci.yml](.github/workflows/ci.yml)).

## License

COCL 1.0 — see [LICENSE](LICENSE) and [DISCLAIMER.md](DISCLAIMER.md). Commercial use → licensing@cognis.digital
