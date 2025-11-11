# SUSHI CLI Tool Usage Guide

## Overview

The `sushi-submit` CLI tool allows you to submit SUSHI analysis jobs from the command line without using the web interface. It communicates with the SUSHI backend API to register datasets and submit jobs.

## Installation

The CLI tool is located at `bin/sushi-submit`. Make sure it's executable:

```bash
chmod +x bin/sushi-submit
```

## Prerequisites

1. **Backend Server**: The SUSHI backend must be running and accessible
2. **Authentication Token** (if authentication is enabled): Obtain a JWT token by logging in via the API

## Basic Usage

### Getting Help

```bash
./bin/sushi-submit --help
```

### Required Options

- `-a, --app APP_NAME`: SUSHI application name (e.g., `FastqcApp`)
- Either `-d, --dataset-id ID` OR `-D, --dataset-file FILE`: Input dataset ID (existing) or TSV file to register

### Common Options

- `-p, --parameter-file FILE`: Parameter TSV file
- `-P, --param KEY=VALUE`: Parameter as key=value (can be specified multiple times)
- `-o, --output-name NAME`: Output dataset name
- `-c, --comment COMMENT`: Comment/description
- `--project-number NUMBER`: Project number (required when using `--dataset-file`)
- `-u, --backend-url URL`: Backend URL (default: `http://localhost:4050`)
- `-t, --token TOKEN`: JWT authentication token
- `-v, --verbose`: Verbose output

## Environment Variables

- `SUSHI_BACKEND_URL`: Default backend URL (overridden by `-u` option)
- `SUSHI_TOKEN`: Default authentication token (overridden by `-t` option)

## Examples

### Example 1: Submit Job with Existing Dataset ID

```bash
./bin/sushi-submit \
  -a FastqcApp \
  -d 9 \
  -P cores=8 \
  -P ram=15 \
  -P scratch=100 \
  -P paired=false \
  -P showNativeReports=false \
  -o FastQC_result \
  -c "Quality control analysis"
```

### Example 2: Register Dataset from TSV and Submit Job

```bash
./bin/sushi-submit \
  -a FastqcApp \
  -D /srv/gstore/projects/p35611/ventricles_100k/test_masa_dataset.tsv \
  --project-number 35611 \
  -P cores=8 \
  -P ram=15 \
  -P scratch=100 \
  -P paired=true \
  -P showNativeReports=false \
  -o FastQC_result \
  -c "Quality control for ventricles dataset"
```

### Example 3: Using Parameter File

Create a parameter file `fastqc_params.tsv`:

```tsv
cores	8
ram	15
scratch	100
paired	true
showNativeReports	false
```

Then submit:

```bash
./bin/sushi-submit \
  -a FastqcApp \
  -d 9 \
  -p fastqc_params.tsv \
  -o FastQC_result
```

### Example 4: Override Parameters from File with Command-Line Options

```bash
./bin/sushi-submit \
  -a FastqcApp \
  -d 9 \
  -p fastqc_params.tsv \
  -P cores=16 \
  -P ram=30 \
  -o FastQC_result
```

In this example, `cores` and `ram` from the parameter file will be overridden by the command-line values.

### Example 5: With Authentication Token

```bash
export SUSHI_TOKEN="your_jwt_token_here"

./bin/sushi-submit \
  -a FastqcApp \
  -d 9 \
  -P cores=8 \
  -P ram=15 \
  -o FastQC_result
```

Or specify token directly:

```bash
./bin/sushi-submit \
  -a FastqcApp \
  -d 9 \
  -t "your_jwt_token_here" \
  -P cores=8 \
  -P ram=15 \
  -o FastQC_result
```

### Example 6: Verbose Output

```bash
./bin/sushi-submit \
  -a FastqcApp \
  -d 9 \
  -P cores=8 \
  -v
```

This will show detailed information about the submission process.

## TSV File Formats

### Dataset TSV Format

The dataset TSV file should have:
- First row: Column headers (tab-separated)
- Subsequent rows: Data rows (tab-separated)

Example:

```tsv
Name	Read1 [File]	Read2 [File]	Species	Adapter1	Adapter2	StrandMode	Enrichment Kit	Read Count	Genotype [Factor]	BFabric Info [B-Fabric]	Order Id [B-Fabric]
mut11	p35611/ventricles_100k/MutantSample_1_R1.fastq.gz	p35611/ventricles_100k/MutantSample_1_R2.fastq.gz	Mus musculus	GATCGGAAGAGCACACGTCTGAACTCCAGTCAC	AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT	both	poly-A	100000	mut	test1	35755
mut22	p35611/ventricles_100k/MutantSample_2_R1.fastq.gz	p35611/ventricles_100k/MutantSample_2_R2.fastq.gz	Mus musculus	GATCGGAAGAGCACACGTCTGAACTCCAGTCAC	AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT	both	poly-A	100000	mut	test2	35755
```

**Note**: The project number can be extracted from file paths (e.g., `p35611/...`) or specified explicitly with `--project-number`.

### Parameter TSV Format

The parameter TSV file should have two columns:
- Column 1: Parameter name
- Column 2: Parameter value

Example:

```tsv
cores	8
ram	15
scratch	100
paired	false
showNativeReports	false
```

## Parameter Value Types

The CLI tool automatically converts parameter values to appropriate types:

- `true` / `false` → Boolean
- Integer numbers (e.g., `8`, `15`) → Integer
- Decimal numbers (e.g., `3.14`) → Float
- Other values → String

## Error Handling

The CLI tool will exit with a non-zero status code if an error occurs. Common errors:

- **Missing required options**: The tool will show an error message and exit
- **Invalid TSV format**: The API will return an error message
- **API errors**: Network errors or API validation errors will be displayed
- **Authentication errors**: If authentication is required but token is missing or invalid

## Output

On successful submission, the tool outputs:

```
Job submitted successfully!
Job ID: 211
Status: CREATED
Output Dataset ID: 281
Output Dataset Name: FastQC_result
```

## Integration with Scripts

The CLI tool can be easily integrated into shell scripts:

```bash
#!/bin/bash

JOB_ID=$(./bin/sushi-submit \
  -a FastqcApp \
  -d 9 \
  -P cores=8 \
  -P ram=15 \
  -o FastQC_result 2>&1 | grep "Job ID:" | awk '{print $3}')

echo "Submitted job: $JOB_ID"
```

## Troubleshooting

### Project Number Not Found

If you see an error about project number not being found:

1. Check if the TSV file contains project paths (e.g., `p35611/...`)
2. Explicitly specify the project number: `--project-number 35611`

### Authentication Errors

If authentication is enabled:

1. Obtain a JWT token by logging in via the API:
   ```bash
   curl -X POST http://localhost:4050/api/v1/auth/login \
     -H "Content-Type: application/json" \
     -d '{"login":"your_username","password":"your_password"}'
   ```
2. Set the token: `export SUSHI_TOKEN="your_token_here"`

### Network Errors

If you see network errors:

1. Verify the backend is running: `curl http://localhost:4050/api/v1/hello`
2. Check the backend URL: `-u http://your-backend-url:port`

## See Also

- [Job Submission API Documentation](./api-job-submission-endpoint.md)
- [Dataset API Documentation](./api-datasets-endpoints.md)

