# FIX rules covered by fixwval

This document is an honest, exact statement of what `fixwval` validates today.
It deliberately calls out what is **not** covered so you don't over-trust it.

## Versions

`fixwval` recognizes these `BeginString` (tag 8) values and echoes the version
in its report:

- **FIX.4.2**
- **FIX.4.4**
- **FIXT.1.1** — the session-layer BeginString used by FIX 5.0 / 5.0SP1 / 5.0SP2.

Structural rules (header order, BodyLength, CheckSum), the MsgType table, the
required-field tables, and the enum tables are applied uniformly across these
versions. The tool does **not** currently branch its required-field or enum
tables per version — the encoded rules are the common core that holds across
4.2/4.4/5.0 for the message types below. Version-specific dictionaries (e.g.
4.4-only tags, 5.0SP2 components) are on the roadmap (see "Not yet covered").

## Structural rules (all versions)

| Rule | Detail |
|------|--------|
| Field structure | Every field must be `tag=value`; `tag` must be all digits. |
| Header order | Tag **8** (BeginString) first, **9** (BodyLength) second, **35** (MsgType) third. |
| Trailer | Tag **10** (CheckSum) must be the last field and exactly 3 digits. |
| **BodyLength (9)** | Must equal the byte count from the first byte after the SOH terminating `9=<val>` up to and including the SOH before `10=`. Delimiter-agnostic: pipe and SOH are each one byte. |
| **CheckSum (10)** | Must equal `(sum of every byte up to and including the SOH before 10=) mod 256`, formatted as a 3-digit zero-padded string. |

The BodyLength and CheckSum algorithms compute against a **canonical SOH stream**
(each field's `tag=value` plus a single 1-byte delimiter), so a pipe-delimited
fixture and its real-SOH equivalent produce identical results.

## MsgType (35) recognition

Recognized message types (reported with a friendly name; unknown values raise
`UNKNOWN_MSGTYPE`):

Session-level: `0` Heartbeat, `1` TestRequest, `2` ResendRequest, `3` Reject,
`4` SequenceReset, `5` Logout, `A` Logon.

Application: `D` NewOrderSingle, `8` ExecutionReport, `9` OrderCancelReject,
`F` OrderCancelRequest, `G` OrderCancelReplaceRequest, `V` MarketDataRequest,
`j` BusinessMessageReject.

## Required-field rules

**Session-level (checked on every message):** `49` SenderCompID, `56` TargetCompID,
`34` MsgSeqNum, `52` SendingTime.

**Per MsgType:**

| MsgType | Required tags checked |
|---------|-----------------------|
| `A` Logon | 98 EncryptMethod, 108 HeartBtInt |
| `D` NewOrderSingle | 11 ClOrdID, 55 Symbol, 54 Side, 60 TransactTime, 40 OrdType, 38 OrderQty |
| `8` ExecutionReport | 37 OrderID, 17 ExecID, 150 ExecType, 39 OrdStatus, 55 Symbol, 54 Side |
| `F` OrderCancelRequest | 41 OrigClOrdID, 11 ClOrdID, 55 Symbol, 54 Side |
| `G` OrderCancelReplaceRequest | 41 OrigClOrdID, 11 ClOrdID, 55 Symbol, 54 Side, 38 OrderQty, 40 OrdType |
| `3` Reject | 45 RefSeqNum |
| `1` TestRequest | 112 TestReqID |

## Enumerated-field checks

For these tags, the value must be in the encoded legal set (else `BAD_ENUM`):

| Tag | Field | Legal values |
|-----|-------|--------------|
| 54 | Side | 1–9 |
| 40 | OrdType | 1–9, D |
| 59 | TimeInForce | 0–7 |
| 39 | OrdStatus | 0–9, A–E |
| 150 | ExecType | 0–9, A–I |
| 98 | EncryptMethod | 0–6 |

## Data-type checks

| Check | Tags |
|-------|------|
| Integer (all digits) | 9 BodyLength, 34 MsgSeqNum, 98 EncryptMethod, 108 HeartBtInt |
| UTCTimestamp `YYYYMMDD-HH:MM:SS[.sss]` | 52 SendingTime, 60 TransactTime |

The timestamp check verifies length ≥ 17, the `-`/`:`/`:` separators at the
correct offsets, and that the date/time positions are digits. It does **not**
range-check (e.g. month ≤ 12) or validate the optional millisecond fraction's
precision.

## Not yet covered (honest limitations)

- **Repeating groups** — `NoPartyIDs` (453), `NoMDEntries` (268), etc. are not
  parsed as groups; their count tag is treated as a plain integer. On the roadmap.
- **Version-specific dictionaries** — required-field/enum tables are a common
  core, not per-version 4.2 vs 4.4 vs 5.0SP2 dictionaries.
- **Session sequencing** — no MsgSeqNum gap detection, ResendRequest/GapFill
  logic, or PossDupFlag handling across a stream. `fixwval` validates messages,
  not the session state machine. On the roadmap.
- **Price/qty semantic ranges** — decimal fields are not range- or tick-checked.
- **User-defined / custom tags** (≥ 5000) — accepted structurally, not dictionary-checked.
- **FIXML / tag-value XML** — only the classic tag=value encoding is parsed.
- **Encryption / signature fields** (89, 93) — not verified.

If a message passes `fixwval`, it is **structurally and header-consistent** and
carries the required fields and legal enums for the checks above — it is **not**
a guarantee of full dictionary conformance for your counterparty's FIX profile.
