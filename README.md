# fixwval

**COBOL (GnuCOBOL)** — Fixed-width record validator — verifies a numeric field is present & all-digits in every record.

[![ci](https://github.com/cognis-digital/fixwval/actions/workflows/ci.yml/badge.svg)](https://github.com/cognis-digital/fixwval/actions/workflows/ci.yml)
![lang](https://img.shields.io/badge/lang-COBOL-informational)
![license](https://img.shields.io/badge/license-COCL%201.0-2ea043)

Part of the **[Cognis Neural Suite](https://github.com/cognis-digital)** — 370+ single-purpose, self-hostable tools. Like every tool in the suite, `fixwval` is single-purpose, emits machine-readable JSON, and exits non-zero when it finds something (CI-friendly).

## Build / run

```bash
cobc -x -o fixwval fixwval.cob
./fixwval records.dat 5 4
```

## Usage

```
fixwval <datafile> <numStart> <numLen>
  numStart   1-based column where the numeric field begins
  numLen     width of the numeric field
```

## Output

A JSON object on stdout. Exit code **2** when findings exist, **0** when clean, **1** on error — so you can gate CI/pipelines on it.

## License

COCL 1.0 — see [LICENSE](LICENSE). Commercial use → licensing@cognis.digital
