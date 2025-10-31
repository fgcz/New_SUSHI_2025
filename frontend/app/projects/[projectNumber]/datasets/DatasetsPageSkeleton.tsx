export default function DatasetsPageSkeleton() {
  return (
    <div className="container mx-auto px-6 py-8">
      <div className="animate-pulse">
        {/* Title skeleton */}
        <div className="h-8 bg-gray-200 rounded w-64 mb-6"></div>
        
        {/* Search controls skeleton */}
        <div className="mb-4 flex items-center gap-4">
          <div className="flex items-center gap-2">
            <div className="h-4 bg-gray-200 rounded w-12"></div>
            <div className="h-8 bg-gray-200 rounded w-16"></div>
            <div className="h-4 bg-gray-200 rounded w-16"></div>
          </div>
          <div className="flex items-center gap-2">
            <div className="h-10 bg-gray-200 rounded w-48"></div>
            <div className="h-10 bg-gray-200 rounded w-20"></div>
          </div>
        </div>

        {/* Table skeleton */}
        <div className="overflow-x-auto">
          <div className="min-w-full border rounded-lg">
            {/* Table header skeleton */}
            <div className="bg-gray-100 border-b">
              <div className="flex">
                <div className="p-2 border-r flex-1 min-w-16">
                  <div className="h-4 bg-gray-300 rounded w-8"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-32">
                  <div className="h-4 bg-gray-300 rounded w-12"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-24">
                  <div className="h-4 bg-gray-300 rounded w-16"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-20">
                  <div className="h-4 bg-gray-300 rounded w-14"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-20">
                  <div className="h-4 bg-gray-300 rounded w-16"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-20">
                  <div className="h-4 bg-gray-300 rounded w-14"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-16">
                  <div className="h-4 bg-gray-300 rounded w-8"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-24">
                  <div className="h-4 bg-gray-300 rounded w-14"></div>
                </div>
                <div className="p-2 flex-1 min-w-24">
                  <div className="h-4 bg-gray-300 rounded w-18"></div>
                </div>
              </div>
            </div>
            
            {/* Table rows skeleton */}
            {[...Array(10)].map((_, i) => (
              <div key={i} className={`border-b ${i % 2 === 0 ? 'bg-white' : 'bg-gray-50'}`}>
                <div className="flex">
                  <div className="p-2 border-r flex-1 min-w-16">
                    <div className="h-4 bg-gray-200 rounded w-12"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-32">
                    <div className="h-4 bg-gray-200 rounded w-24"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-24">
                    <div className="h-4 bg-gray-200 rounded w-20"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-20">
                    <div className="h-4 bg-gray-200 rounded w-16"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-20">
                    <div className="h-4 bg-gray-200 rounded w-12"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-20">
                    <div className="h-4 bg-gray-200 rounded w-8"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-16">
                    <div className="h-4 bg-gray-200 rounded w-16"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-24">
                    <div className="h-4 bg-gray-200 rounded w-20"></div>
                  </div>
                  <div className="p-2 flex-1 min-w-24">
                    <div className="h-4 bg-gray-200 rounded w-16"></div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Pagination skeleton */}
        <div className="mt-4 flex items-center justify-between gap-2">
          <div className="h-4 bg-gray-200 rounded w-48"></div>
          <div className="flex items-center gap-2">
            <div className="h-8 bg-gray-200 rounded w-16"></div>
            <div className="h-4 bg-gray-200 rounded w-24"></div>
            <div className="h-8 bg-gray-200 rounded w-16"></div>
          </div>
        </div>
      </div>
    </div>
  );
}