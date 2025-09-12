'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';

export default function DatasetDetailPlaceholder() {
  const params = useParams<{ projectNumber: string; datasetId: string }>();
  const { projectNumber, datasetId } = params;

  return (
    <div className="container mx-auto px-6 py-8">
      <h1 className="text-2xl font-bold mb-4">Dataset {datasetId}</h1>
      <p className="text-gray-700 mb-6">This is a temporary placeholder page for dataset details.</p>
      <Link href={`/projects/${projectNumber}/datasets`} className="text-blue-600 hover:underline">Back to list</Link>
    </div>
  );
}


