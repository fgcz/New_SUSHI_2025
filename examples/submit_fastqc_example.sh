#!/bin/bash
# Example script for submitting FastqcApp job using sushi-submit CLI tool

# Set backend URL (optional, defaults to http://localhost:4050)
export SUSHI_BACKEND_URL="${SUSHI_BACKEND_URL:-http://localhost:4050}"

# Set authentication token if needed (optional)
# export SUSHI_TOKEN="your_jwt_token_here"

# Example 1: Submit with existing dataset ID
echo "Example 1: Submit with existing dataset ID"
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

echo ""
echo "---"
echo ""

# Example 2: Register dataset from TSV and submit
echo "Example 2: Register dataset from TSV and submit"
./bin/sushi-submit \
  -a FastqcApp \
  -D /srv/gstore/projects/p35611/ventricles_100k/test_masa_dataset.tsv \
  --project-number 35611 \
  -p examples/fastqc_params.tsv \
  -P paired=true \
  -o FastQC_result \
  -c "Quality control for ventricles dataset" \
  -v

echo ""
echo "---"
echo ""

# Example 3: Using parameter file only
echo "Example 3: Using parameter file only"
./bin/sushi-submit \
  -a FastqcApp \
  -d 9 \
  -p examples/fastqc_params.tsv \
  -o FastQC_result

