"""Job routes - thin handlers delegating to services."""

from fastapi import APIRouter
from pydantic import BaseModel

from app.api.deps import CurrentUserDep, JobServiceDep, JobSubmissionServiceDep

router = APIRouter()


class NextDatasetRequest(BaseModel):
    name: str
    comment: str | None = None


class JobSubmitRequest(BaseModel):
    project_number: int
    dataset_id: int
    app_name: str
    next_dataset: NextDatasetRequest
    parameters: dict


@router.get("/")
def get_all_jobs(
    current_user: CurrentUserDep,
    service: JobServiceDep,
    page: int = 1,
    per: int = 50,
    status: str | None = None,
    user: str | None = None,
    dataset_name: str | None = None,
) -> dict:
    """Get all jobs paginated with optional filters."""
    return service.get_all_paginated(page, per, status, user, dataset_name)


@router.get("/{job_id}")
def get_job(
    job_id: int,
    current_user: CurrentUserDep,
    service: JobServiceDep,
) -> dict:
    """Get full job details by ID."""
    return service.get_by_id(job_id)


@router.get("/{job_id}/script")
def get_job_script(
    job_id: int,
    current_user: CurrentUserDep,
    service: JobServiceDep,
) -> dict:
    """Get job script content."""
    script = service.get_script(job_id)
    return {"script": script}


@router.get("/{job_id}/logs")
def get_job_logs(
    job_id: int,
    current_user: CurrentUserDep,
    service: JobServiceDep,
) -> dict:
    """Get job logs (stdout and stderr separately)."""
    return service.get_logs(job_id)


@router.get("/{job_id}/script_mock")
def get_job_script_mock(
    job_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Get mock job script content for development."""
    mock_script = f'''#!/usr/bin/env python3
"""
Data Processing Script - Customer Analytics Q3
Job ID: {job_id}
Author: {current_user.login}
Created: 2024-10-08
"""

import pandas as pd
import numpy as np
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def load_data(file_path):
    """Load customer data from CSV file"""
    logger.info(f"Loading data from {{file_path}}")
    df = pd.read_csv(file_path)
    logger.info(f"Successfully loaded {{len(df)}} records")
    return df

def process_analytics(df):
    """Process customer analytics data"""
    logger.info("Starting analytics processing")
    df['total_spent'] = df['purchase_amount'] * df['quantity']
    df['customer_segment'] = pd.cut(
        df['total_spent'],
        bins=[0, 100, 500, 1000, np.inf],
        labels=['Bronze', 'Silver', 'Gold', 'Platinum']
    )
    summary = df.groupby('customer_segment').agg({{
        'total_spent': ['count', 'mean', 'sum'],
        'customer_id': 'nunique'
    }}).round(2)
    logger.info("Analytics processing completed")
    return df, summary

def main():
    """Main execution function"""
    logger.info(f"Starting job {job_id}")
    data = load_data('/data/customer_data_q3.csv')
    processed_data, summary = process_analytics(data)
    output_path = f'/output/analytics_results_{job_id}.csv'
    processed_data.to_csv(output_path, index=False)
    logger.info(f"Results saved to {{output_path}}")
    logger.info("Job completed successfully")

if __name__ == "__main__":
    main()
'''
    return {"script": mock_script}


@router.get("/{job_id}/logs_mock")
def get_job_logs_mock(
    job_id: int,
    current_user: CurrentUserDep,
) -> dict:
    """Get mock job logs for development."""
    mock_stdout = f'''2024-10-08 09:15:30,123 - INFO - Starting job {job_id} - Customer Analytics Q3
2024-10-08 09:15:30,125 - INFO - Initializing data processing pipeline
2024-10-08 09:15:30,126 - INFO - Loading data from /data/customer_data_q3.csv
2024-10-08 09:15:31,456 - INFO - Successfully loaded 15,247 records
2024-10-08 09:15:31,457 - INFO - Data validation passed: 15,247 valid records, 0 invalid records
2024-10-08 09:15:31,458 - INFO - Starting analytics processing
2024-10-08 09:15:31,890 - INFO - Calculating customer metrics for 15,247 customers
2024-10-08 09:15:32,234 - INFO - Customer segmentation complete:
2024-10-08 09:15:32,235 - INFO -   Bronze: 8,123 customers (53.3%)
2024-10-08 09:15:32,236 - INFO -   Silver: 4,567 customers (29.9%)
2024-10-08 09:15:32,237 - INFO -   Gold: 2,234 customers (14.7%)
2024-10-08 09:15:32,238 - INFO -   Platinum: 323 customers (2.1%)
2024-10-08 09:15:32,567 - INFO - Generating summary statistics
2024-10-08 09:15:33,123 - INFO - Summary statistics generated successfully
2024-10-08 09:15:33,456 - INFO - Analytics processing completed
2024-10-08 09:15:33,789 - INFO - Saving processed data to /output/analytics_results_{job_id}.csv
2024-10-08 09:15:34,234 - INFO - Data export completed: 15,247 records written
2024-10-08 09:15:35,456 - INFO - Results saved to /output/analytics_results_{job_id}.csv
2024-10-08 09:15:35,789 - INFO - Performance metrics:
2024-10-08 09:15:35,790 - INFO -   Total execution time: 5.667 seconds
2024-10-08 09:15:35,791 - INFO -   Records processed per second: 2,691
2024-10-08 09:15:35,792 - INFO -   Memory usage: 234.5 MB peak
2024-10-08 09:15:35,793 - INFO -   CPU usage: 87% average
2024-10-08 09:15:35,794 - INFO - Job completed successfully
2024-10-08 09:15:35,795 - INFO - Cleanup: temporary files removed
2024-10-08 09:15:35,796 - INFO - Exit code: 0'''

    mock_stderr = f'''2024-10-08 09:15:30,124 - WARNING - Config file not found, using defaults
2024-10-08 09:15:31,200 - WARNING - 3 records had missing values, filled with defaults
2024-10-08 09:15:34,100 - WARNING - Output directory already exists, files may be overwritten'''

    return {"stdout": mock_stdout, "stderr": mock_stderr}


@router.post("/")
def submit_job(
    request: JobSubmitRequest,
    current_user: CurrentUserDep,
    submission_service: JobSubmissionServiceDep,
) -> dict:
    """Submit a new job for execution."""
    # Extract from request for clarity
    dataset_id = request.dataset_id
    project_number = request.project_number
    user_login = current_user.login

    app_name = request.app_name
    params = request.parameters
    next_dataset_name = request.next_dataset.name
    next_dataset_comment = request.next_dataset.comment

    return submission_service.submit(
        # Identity
        dataset_id=dataset_id,
        project_number=project_number,
        user_login=user_login,
        # App configuration
        app_name=app_name,
        params=params,
        next_dataset_name=next_dataset_name,
        next_dataset_comment=next_dataset_comment,
    )
