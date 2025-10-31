'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import EditableTable from './EditableTable';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';
import { useDatasetBase, useDatasetSamples } from '@/lib/hooks';
import SamplesEditPageSkeleton from './SamplesEditPageSkeleton';
import DatasetInfoCard from '../../DatasetInfoCard';

export default function SamplesEditPage() {
  const params = useParams<{ projectNumber: string; datasetId: string }>();
  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);

  const { dataset, isLoading: isDatasetLoading, error: datasetError, notFound: datasetNotFound } = useDatasetBase(datasetId);
  const { samples: datasetSamples, isLoading: isDatasetSamplesLoading, error: datasetSamplesError } = useDatasetSamples(datasetId);

  if (isDatasetLoading) return <SamplesEditPageSkeleton />;
  
  if (datasetError) return (
    <div className="container mx-auto px-6 py-8">
      <div className="text-center py-12">
        <div className="text-red-600 text-lg font-medium mb-2">Failed to load dataset</div>
        <p className="text-gray-500 mb-4">There was an error loading the dataset information.</p>
        <Link href={`/projects/${projectNumber}/datasets/${datasetId}`} className="text-blue-600 hover:underline">
          ← Back to Dataset
        </Link>
      </div>
    </div>
  );

  if (datasetNotFound || !dataset) {
    return (
      <div className="container mx-auto px-6 py-8">
        <h1 className="text-2xl font-bold mb-4 text-red-600">Dataset Not Found</h1>
        <p className="text-gray-700 mb-6">Dataset {datasetId} was not found in project {projectNumber}.</p>
        <Link href={`/projects/${projectNumber}/datasets`} className="text-blue-600 hover:underline">← Back to Datasets</Link>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-6 py-8">

      <Breadcrumbs items={[
        { label: 'Projects', href: '/projects' },
        { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
        { label: 'Datasets', href: `/projects/${projectNumber}/datasets` },
        { label: dataset.name, href: `/projects/${projectNumber}/datasets/${datasetId}`},
        { label: "Edit Samples", active: true }
      ]} />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Edit Samples - {dataset.name}</h1>
        <Link 
          href={`/projects/${projectNumber}/datasets/${datasetId}`} 
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          ← Back to Dataset
        </Link>
      </div>

      <div className="space-y-6">
        {/* Dataset Details Section - Read Only (Same as original view) */}
        <DatasetInfoCard dataset={dataset} />

        {/* Editable Samples Section */}
        <div className="bg-white border rounded-lg overflow-hidden">
          <div className="px-6 py-4 bg-gray-50 border-b">
            <h2 className="text-lg font-semibold">Edit Samples Table</h2>
            <p className="text-sm text-gray-600 mt-1">
              Edit sample data directly in the table below
            </p>
          </div>
          <div className="p-6">
            <EditableTable
              initialSamples={datasetSamples || []}
              projectNumber={projectNumber}
              datasetId={datasetId}
              isLoading={isDatasetSamplesLoading}
              error={datasetSamplesError}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
