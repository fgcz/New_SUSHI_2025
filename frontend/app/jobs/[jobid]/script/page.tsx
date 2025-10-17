'use client';

import { useParams } from 'next/navigation';
import Link from 'next/link';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';


export default function JobScriptPage() {
  const params = useParams<{ jobid: string }>();
  const jobId = params.jobid;

  const hardcodedScript = `#!/usr/bin/env python3
"""
Data Processing Script - Customer Analytics Q3
Job ID: ${jobId}
Author: rdomi
Created: 2024-10-08
"""

import pandas as pd
import numpy as np
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def load_data(file_path):
    """Load customer data from CSV file"""
    logger.info(f"Loading data from {file_path}")
    try:
        df = pd.read_csv(file_path)
        logger.info(f"Successfully loaded {len(df)} records")
        return df
    except Exception as e:
        logger.error(f"Failed to load data: {e}")
        raise

def process_analytics(df):
    """Process customer analytics data"""
    logger.info("Starting analytics processing")
    
    # Calculate customer metrics
    df['total_spent'] = df['purchase_amount'] * df['quantity']
    df['customer_segment'] = pd.cut(df['total_spent'], 
                                   bins=[0, 100, 500, 1000, np.inf], 
                                   labels=['Bronze', 'Silver', 'Gold', 'Platinum'])
    
    # Generate summary statistics
    summary = df.groupby('customer_segment').agg({
        'total_spent': ['count', 'mean', 'sum'],
        'customer_id': 'nunique'
    }).round(2)
    
    logger.info("Analytics processing completed")
    return df, summary

def main():
    """Main execution function"""
    logger.info(f"Starting job {jobId} - Customer Analytics Q3")
    
    try:
        # Load and process data
        data = load_data('/data/customer_data_q3.csv')
        processed_data, summary = process_analytics(data)
        
        # Save results
        output_path = f'/output/analytics_results_{jobId}.csv'
        processed_data.to_csv(output_path, index=False)
        
        logger.info(f"Results saved to {output_path}")
        logger.info("Job completed successfully")
        
    except Exception as e:
        logger.error(f"Job failed: {e}")
        raise

if __name__ == "__main__":
    main()`;
    const projectNumber = 12312;
  return (
    <div className="container mx-auto px-6 py-8">
      <Breadcrumbs items={[
        { label: 'Projects', href: '/projects' },
        { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
        { label: 'Jobs', href: `/projects/${projectNumber}/jobs` },
        { label: `Job ${jobId}` },
        { label: "Script", active: true }
      ]} />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Job {jobId} - Script</h1>
        <button 
          onClick={() => window.history.back()} 
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          ← Back
        </button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <div className="px-4 py-3 bg-gray-50 border-b border-gray-200">
          <h2 className="text-lg font-medium text-gray-900">Script Content</h2>
          <p className="text-sm text-gray-500">data_processing.py</p>
        </div>
        <div className="p-0">
          <pre style={{wordWrap: 'break-word', whiteSpace: 'pre-wrap'}} className="text-sm text-gray-900 p-4 overflow-x-auto">
            {hardcodedScript}
          </pre>
        </div>
      </div>
    </div>
  );
}
