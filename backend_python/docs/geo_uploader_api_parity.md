# GeoUploader API parity

GeoUploader (`/misc/fgcz01/geo-uploader/prod`) previously required a direct MySQL
connection to the SUSHI MariaDB via `SushiService`. Every database call it makes
has been replaced by an HTTP endpoint on the Python backend under `/api/internal/legacy/`.

---

## Endpoint mapping

| SushiService method | SQL | API endpoint | Returns |
|---|---|---|---|
| `get_project_datasets(project_id)` | `SELECT data_sets.id, name, parent_id FROM data_sets JOIN projects … WHERE projects.number = %s` | `GET /api/internal/legacy/projects/{number}/datasets` | `[{id, name, parent_id}]` |
| `get_project_from_dataset_id(dataset_id)` | `SELECT projects.number FROM data_sets JOIN projects … WHERE data_sets.id = %s` | `GET /api/internal/legacy/datasets/{id}/project` | `{project_number}` |
| `query_key_value_from_dataset_id(dataset_id)` | `SELECT key_value FROM samples WHERE data_set_id = %s` | `GET /api/internal/legacy/datasets/{id}/samples` | `[{...parsed sample dict...}]` |
| `get_dataset_column_names(dataset_id)` | same query as above | same endpoint — derive column names from the keys of the first item | |
| `get_dataset_id_from_bfabric_dataset_id(bfabric_id)` | `SELECT id FROM data_sets WHERE bfabric_id = %s` | `GET /api/internal/legacy/datasets/by-bfabric/{bfabric_id}` | `{dataset_id}` |

`get_dataset_column_names` and `query_key_value_from_dataset_id` are collapsed into
one endpoint — they run the same query, and the caller derives column names from the
returned sample list rather than making a separate call.

Ruby Hash#inspect strings (`{"key"=>"value"}`) are parsed to plain dicts by the
backend before returning. GeoUploader receives clean JSON and no longer needs its
`_ruby_to_df` conversion logic.

---

## Parity achieved

All five `SushiService` methods are covered. GeoUploader does not need a direct
database connection to operate. The `mysql-connector-python` dependency, all
`_setup_connection` / `_teardown_connection` calls, and the four
`SUSHI_DB_*` config keys can be removed from GeoUploader entirely.

---

## Steps for GeoUploader to migrate

### 1. Add a SUSHI API client

Replace `SushiService` with a thin HTTP client. It needs one config value:

```python
SUSHI_API_URL = "http://fgcz-h-083:4071/api/internal"
SUSHI_API_KEY = os.environ.get("SUSHI_API_KEY", "")
```

A minimal wrapper:

```python
import requests

class SushiApiClient:
    def __init__(self, base_url, api_key):
        self.base_url = base_url
        self.headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}

    def _get(self, path):
        response = requests.get(f"{self.base_url}{path}", headers=self.headers, timeout=30)
        response.raise_for_status()
        return response.json()

    def get_project_datasets(self, project_number):
        return self._get(f"/legacy/projects/{project_number}/datasets")

    def get_project_from_dataset_id(self, dataset_id):
        return self._get(f"/legacy/datasets/{dataset_id}/project")["project_number"]

    def query_key_value_from_dataset_id(self, dataset_id):
        # returns list of dicts — no Ruby parsing needed
        return self._get(f"/legacy/datasets/{dataset_id}/samples")

    def get_dataset_column_names(self, dataset_id):
        samples = self._get(f"/legacy/datasets/{dataset_id}/samples")
        return list(samples[0].keys()) if samples else []

    def get_dataset_id_from_bfabric_dataset_id(self, bfabric_id):
        return self._get(f"/legacy/datasets/by-bfabric/{bfabric_id}")["dataset_id"]
```

The method signatures match the original `SushiService` exactly so call sites in
`auth_views.py`, `upload_views.py`, `validators.py`, and `sample_service.py` need
no changes — only the instantiation changes.

### 2. Replace the instantiation

Every `SushiService()` call becomes `SushiApiClient(SUSHI_API_URL, SUSHI_API_KEY)`.
There are five call sites:

| File | Line | Change |
|---|---|---|
| `views/auth_views.py` | `sushi_service = SushiService()` | swap class |
| `views/upload_views.py` | three separate `SushiService()` instantiations | swap class |
| `services/sample_service.py` | `self.sushi_service = sushi_service or SushiService()` | swap default |
| `utils/validators.py` | `sushi_service = SushiService()` | swap class |

### 3. Remove the DB config and dependency

From `config.py`, remove:
```python
SUSHI_DB_HOST
SUSHI_DB_USER
SUSHI_DB_PASSWORD
SUSHI_DB_NAME
```

From `environment.yml` / `requirements.txt`, remove `mysql-connector-python`.

From `.env` / `.env.example`, replace the four `SUSHI_DB_*` vars with:
```
SUSHI_API_URL=http://fgcz-h-083:4071/api/internal
SUSHI_API_KEY=<key>
```

### 4. Remove `_ruby_to_df`

The `_ruby_to_df` method in `SushiService` and any callers that relied on receiving
a DataFrame can now receive a list of dicts directly from the API. Anywhere a
DataFrame was constructed from the result, build it with `pd.DataFrame(samples)`
instead of `pd.DataFrame(sushi_service._ruby_to_df(...))`.

### 5. Delete `sushi_service.py`

Once all call sites are migrated and tested, `geo_uploader/services/external/sushi_service.py`
can be deleted.
