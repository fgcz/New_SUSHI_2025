#!/bin/bash
# Test script for Job Submission API

set -e

# Configuration
BASE_URL="http://localhost:4050/api/v1"
DATASET_ID=9  # ventricles_100k dataset
APP_NAME="FastqcApp"

echo "=========================================="
echo "Job Submission API Test Script"
echo "=========================================="
echo ""

# Step 1: Check dataset exists
echo "Step 1: Checking dataset..."
echo "GET ${BASE_URL}/datasets/${DATASET_ID}"
curl -s "${BASE_URL}/datasets/${DATASET_ID}" | jq '.'
echo ""
echo "----------------------------------------"
echo ""

# Step 2: Submit job
echo "Step 2: Submitting job..."
echo "POST ${BASE_URL}/jobs"
JOB_RESPONSE=$(curl -s -X POST "${BASE_URL}/jobs" \
  -H "Content-Type: application/json" \
  -d '{
    "job": {
      "dataset_id": '"${DATASET_ID}"',
      "app_name": "'"${APP_NAME}"'",
      "parameters": {
        "cores": 8,
        "ram": 15,
        "scratch": 100,
        "paired": false,
        "showNativeReports": false
      },
      "next_dataset_name": "FastQC_test_result",
      "next_dataset_comment": "Test job submission via API"
    }
  }')

echo "${JOB_RESPONSE}" | jq '.'

# Extract job ID
JOB_ID=$(echo "${JOB_RESPONSE}" | jq -r '.job.id')
OUTPUT_DATASET_ID=$(echo "${JOB_RESPONSE}" | jq -r '.output_dataset.id')

if [ "${JOB_ID}" = "null" ] || [ -z "${JOB_ID}" ]; then
  echo ""
  echo "❌ ERROR: Job submission failed!"
  exit 1
fi

echo ""
echo "✅ Job created successfully!"
echo "   Job ID: ${JOB_ID}"
echo "   Output Dataset ID: ${OUTPUT_DATASET_ID}"
echo ""
echo "----------------------------------------"
echo ""

# Step 3: Get job details
echo "Step 3: Fetching job details..."
echo "GET ${BASE_URL}/jobs/${JOB_ID}"
curl -s "${BASE_URL}/jobs/${JOB_ID}" | jq '.'
echo ""
echo "----------------------------------------"
echo ""

# Step 4: List all jobs
echo "Step 4: Listing recent jobs..."
echo "GET ${BASE_URL}/jobs?per=5"
curl -s "${BASE_URL}/jobs?per=5" | jq '.'
echo ""
echo "----------------------------------------"
echo ""

# Step 5: Check output dataset
echo "Step 5: Checking output dataset..."
echo "GET ${BASE_URL}/datasets/${OUTPUT_DATASET_ID}"
curl -s "${BASE_URL}/datasets/${OUTPUT_DATASET_ID}" | jq '.'
echo ""
echo "----------------------------------------"
echo ""

# Step 6: Verify job script was created
echo "Step 6: Verifying job script file..."
SCRIPT_PATH=$(curl -s "${BASE_URL}/jobs/${JOB_ID}" | jq -r '.job.script_path')
echo "Script path: ${SCRIPT_PATH}"

if [ -f "${SCRIPT_PATH}" ]; then
  echo "✅ Script file exists!"
  echo ""
  echo "First 30 lines of script:"
  head -n 30 "${SCRIPT_PATH}"
else
  echo "❌ Script file not found: ${SCRIPT_PATH}"
fi

echo ""
echo "=========================================="
echo "✅ All tests completed successfully!"
echo "=========================================="


