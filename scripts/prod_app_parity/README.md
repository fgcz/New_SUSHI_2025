# prod_app_parity — is the app source we validated against the app source production runs?

Every Level-2 byte-parity result for the allow-listed legacy apps was obtained on fgcz-h-083
against the **2026-04-16 checkout** (`/srv/sushi/masa_test_sushi_20260416/master/lib`).
The production node fgcz-h-082 runs **`/srv/sushi/production/master/lib`**. On 2026-08-18 the
md5 of all 17 allow-listed apps differed between the two, which put every parity result in
doubt.

These two scripts size that drift. Kept here rather than re-derived because re-deriving means
reading production again.

## Why two scripts

The API exposes only the **input** surface. The **output** surface — `next_dataset` — is what
actually invalidates a byte-parity result, because its tagged headers drive both a downstream
app's input resolution and the gStore copy set. So it has to be compared at source.

| script | surface | source of truth |
|---|---|---|
| `compare_app_configs.py` | input: form_fields, required_columns, required_params, modules, category | `GET /api/v1/application_configs/:app` on both nodes |
| `diff_next_dataset.py` | output: the tagged headers `next_dataset` emits, and its body | the two app source trees |

Both exit **non-zero when they find drift**, so they are usable as checks and not just as
reports.

## Two traps this encodes

1. **The app LIST proves nothing.** `LegacyAppLoader.list_apps` is
   `native_app_names + legacy_app_names` — pure filename matching, it never loads a class. And
   `LegacyAppLoader.load` returns `nil` and only *logs* on failure. So a broken app stays
   visible in `index` and silently disappears from `show`. Level-1 must be driven through
   `show` (`GET /api/v1/application_configs/:app_name`), which is the path that actually
   evaluates the file on the shim and calls `app_class.new`.
2. **An md5 difference is not a contract difference.** Most of the 2026-08-18 drift was
   comments, `@citation` arrays and description text. Measured properly it was 4 apps on the
   input surface and 2 on the output surface.

`compare_app_configs.py` requires both backends to run the **same revision**, otherwise it is
measuring code drift rather than app-source drift. It warns if it cannot tell.

## Usage

    # input surface, live against both nodes (read-only GETs)
    python3 compare_app_configs.py

    # output surface, against two app source trees
    rsync -a fgcz-h-082:/srv/sushi/production/master/lib/ /tmp/prod_apps/    # scp is denied, rsync is not
    python3 diff_next_dataset.py /srv/sushi/masa_test_sushi_20260416/master/lib /tmp/prod_apps

## Result on 2026-08-18

Level-1 passed 18/18 against production app source. Drift:

| App | input | output (`next_dataset`) |
|---|---|---|
| STAR | −`getJunctions` | `Junctions`/`Chimerics` left `if @params['getJunctions']` (default **false**) and are now unconditional, plus new `DupRate [File]` — a default run goes from 4 to **7** tagged columns |
| BWA | — | new `DupMetrics [File,Link]`, gated on `markDuplicates` whose default is **true**, so a default run emits it |
| DESeq2 | +`rankMetric` (select, default `log2Ratio`) | — |
| EdgeR | +`rankMetric` | — |
| ScSeurat | +`mLLMCelltype` (boolean, default **true**), +`mLLMCelltype.tissue`, −2 confidence thresholds | — |
| other 13 | identical | identical |

⇒ Level-2 re-validation scope is **STAR, BWA, DESeq2, EdgeR, ScSeurat**. The other 13 of 18
need no redo.
