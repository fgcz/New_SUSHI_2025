# Job Submission Flow

## High-Level Overview

```mermaid
flowchart TD
    subgraph API["API Layer"]
        A[POST /jobs/submit]
    end

    subgraph Services["Service Layer"]
        B[JobSubmissionService.submit]

        subgraph Load["1-2. Load Data"]
            B1[_load_dataset]
            B2[_load_samples]
            B3[_load_project_defaults]
        end

        subgraph Configure["3-5. Configure App"]
            B4[_build_paths]
            B5[app.configure]
            B6[app.set_default_parameters]
            B7[app.adjust_requirements]
        end

        subgraph Validate["6. Validate"]
            V1[validate_columns]
            V2[validate_params]
        end

        subgraph Persist["7-12. Persist"]
            P1[_create_output_dataset]
            P2[_write_input_dataset_tsv]
            P3[_generate_scripts_for_mode]
            P4[_write_parameters_tsv]
            P5[_create_job_record]
            P6[_save_parameters_to_db]
        end

        subgraph Submit["13. Submit"]
            S1[SlurmService.submit]
            S2[SlurmService.submit_job_chain]
        end
    end

    subgraph Domain["Domain Layer (omics_apps/)"]
        D1[MultiOmicsApp.configure]
        D2[MultiOmicsApp.set_default_parameters]
        D3[MultiOmicsApp.adjust_requirements]
        D4[MultiOmicsApp.commands]
        D5[MultiOmicsApp.next_dataset]
        D6[generate_r_heredoc]
    end

    subgraph SLURM["SlurmService"]
        SL1[build_script]
        SL2[write_script]
        SL3[submit / submit_job_chain]
    end

    A --> B
    B --> B1 & B2 & B3
    B1 & B2 & B3 --> B4
    B4 --> B5 --> B6 --> B7
    B5 -.-> D1
    B6 -.-> D2
    B7 -.-> D3
    B7 --> V1 --> V2
    V2 --> P1 --> P2 --> P3
    P3 --> P4 --> P5 --> P6
    P3 -.-> SL1 -.-> SL2
    SL1 -.-> D4 -.-> D6
    SL1 -.-> D5
    P6 --> S1
    S1 -.-> SL3

    classDef implemented fill:#90EE90,stroke:#228B22
    classDef stub fill:#FFB6C1,stroke:#DC143C

    class D1,D2,D3,D4,D5,D6 implemented
    class B1,B2,B3,B4,B5,B6,B7,V1,V2,P1,P2,P3,P4,P5,P6,S1,S2,SL1,SL2,SL3 stub
```

## Implementation Status

```mermaid
flowchart LR
    subgraph Legend
        L1[Implemented]:::implemented
        L2[Stub]:::stub
    end

    classDef implemented fill:#90EE90,stroke:#228B22
    classDef stub fill:#FFB6C1,stroke:#DC143C

    class L1 implemented
    class L2 stub
```

| Step | Component | File | Status |
|------|-----------|------|--------|
| 1 | Load dataset | `job_submission.py` | 🔶 Stub |
| 2 | Load samples | `job_submission.py` | 🔶 Stub |
| 2 | Load project defaults | `job_submission.py` | 🔶 Stub |
| 3 | Build paths | `job_submission.py` | 🔶 Stub |
| 4 | Configure app | `base.py` | ✅ Done |
| 5 | set_default_parameters | `base.py` | ✅ Done |
| 5 | adjust_requirements | `base.py` | ✅ Done |
| 6 | Validate columns | `omics_app_validators.py` | 🔶 Stub |
| 6 | Validate params | `omics_app_validators.py` | 🔶 Stub |
| 7 | Create output dataset | `job_submission.py` | 🔶 Stub |
| 8 | Write input TSV | `job_submission.py` | 🔶 Stub |
| 9 | Generate scripts | `job_submission.py` | 🔶 Stub |
| 9 | Build SLURM script | `slurm_service.py` | 🔶 Stub |
| 9 | → commands() | `base.py` | ✅ Done |
| 9 | → R heredoc | `r_heredoc.py` | ✅ Done |
| 9 | → next_dataset() | `base.py` | ✅ Done |
| 9 | Write script | `slurm_service.py` | 🔶 Stub |
| 10 | Write parameters TSV | `job_submission.py` | 🔶 Stub |
| 11 | Create job record | `job_submission.py` | 🔶 Stub |
| 12 | Save params to DB | `job_submission.py` | 🔶 Stub |
| 13 | Submit to SLURM | `slurm_service.py` | 🔶 Stub |

## Process Modes

```mermaid
flowchart TD
    subgraph DATASET["DATASET Mode"]
        D1[All samples] --> D2[1 script] --> D3[1 job]
    end

    subgraph SAMPLE["SAMPLE Mode"]
        S1[Sample 1] --> S2[Script 1] --> S3[Job 1]
        S4[Sample 2] --> S5[Script 2] --> S6[Job 2]
        S7[Sample N] --> S8[Script N] --> S9[Job N]
        S3 -->|--dependency=afterok| S6
        S6 -->|--dependency=afterok| S9
    end

    subgraph BATCH["BATCH Mode"]
        B1[All samples] --> B2[1 script] --> B3[1 job]
    end
```

## File Locations

```mermaid
flowchart TD
    subgraph omics_apps["omics_apps/ (Domain)"]
        SA1[base.py - MultiOmicsApp class]
        SA2[r_heredoc.py - R script generation]
        SA3[config.py - constants]
        SA4[fastqc.py, countqc.py - apps]
    end

    subgraph services["app/services/ (Orchestration)"]
        SV1[job_submission.py - main orchestrator]
        SV2[slurm_service.py - SLURM interaction]
        SV3[omics_app_validators.py - validation]
    end

    subgraph repos["app/repositories/ (Data Access)"]
        R1[dataset.py]
        R2[job.py]
        R3[sample.py]
    end

    subgraph api["app/api/ (HTTP)"]
        API1[routes/jobs.py]
        API2[serializers/omics_app.py]
    end

    API1 --> SV1
    SV1 --> SV2 & SV3
    SV1 --> R1 & R2 & R3
    SV2 --> SA1
    SA1 --> SA2
    SA4 --> SA1
```
