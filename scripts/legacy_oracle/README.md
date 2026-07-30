# Legacy output-column oracle

Level-2 validation helper: runs the **same inputs** through the legacy SUSHI
`extract_columns` implementation and through the New SUSHI one, then diffs the results.
Legacy is the oracle — New SUSHI matching it bit-for-bit is the contract, because output
datasets produced by the two systems live side by side in the same database.

## Run

```bash
ruby scripts/legacy_oracle/oracle_legacy.rb > /tmp/oracle_legacy.json
ruby scripts/legacy_oracle/oracle_new.rb    > /tmp/oracle_new.json
diff /tmp/oracle_legacy.json /tmp/oracle_new.json && echo IDENTICAL
```

`oracle_legacy.rb` needs a legacy SUSHI checkout. It defaults to
`/srv/sushi/masa_test_sushi_20260416/master/lib` (the same tree `LEGACY_APPS_DIR` points
at on fgcz-h-083); override with `LEGACY_APPS_DIR=...`. `oracle_new.rb` resolves
`backend/lib` relative to this directory; override with `NEW_SUSHI_LIB=...`.

Neither side boots Rails. `oracle_legacy.rb` reads legacy
`SushiApp#get_columns_with_tag` verbatim out of `sushiApp.rb` and `class_eval`s it, so the
oracle cannot drift from legacy via a hand-copy mistake.

## Result 2026-07-30

All 7 cases IDENTICAL, on New SUSHI main @ 5a59486. This closed the follow-up left open by
the 2026-07-21 oracle diff: legacy inherits `[Characteristic]` columns and the input used
back then had none, so the path was unverified. It is verified now — DATASET mode, SAMPLE
mode, `sample_name` per-row pick, the `colnames:` path, the positional-args form, and the
legacy `tags` beats `colnames` precedence quirk all match.

The expectations are pinned as rspec regressions in
`backend/spec/lib/extract_columns_tag_spec.rb`, so a future change that diverges from
legacy fails the suite rather than silently corrupting output datasets.
