export default function SamplesEditPageSkeleton() {
  return (
    <div className="container mx-auto px-6 py-8">
      <div className="animate-pulse">
        {/* Breadcrumb skeleton */}
        <div className="h-4 bg-gray-200 rounded w-48 mb-6"></div>
        
        {/* Title skeleton */}
        <div className="flex items-center justify-between mb-6">
          <div className="h-8 bg-gray-200 rounded w-64"></div>
          <div className="h-8 bg-gray-200 rounded w-32"></div>
        </div>

        <div className="space-y-6">
          {/* Dataset Details skeleton */}
          <div className="bg-white border rounded-lg overflow-hidden">
            <div className="p-6 space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="space-y-3">
                  <div className="h-6 bg-gray-200 rounded w-32 mb-4"></div>
                  {[...Array(5)].map((_, i) => (
                    <div key={i} className="flex justify-between">
                      <div className="h-4 bg-gray-200 rounded w-20"></div>
                      <div className="h-4 bg-gray-200 rounded w-24"></div>
                    </div>
                  ))}
                </div>
                <div className="space-y-3">
                  <div className="h-6 bg-gray-200 rounded w-40 mb-4"></div>
                  {[...Array(3)].map((_, i) => (
                    <div key={i} className="flex justify-between">
                      <div className="h-4 bg-gray-200 rounded w-24"></div>
                      <div className="h-4 bg-gray-200 rounded w-16"></div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>

          {/* Samples Edit skeleton */}
          <div className="bg-white border rounded-lg overflow-hidden">
            <div className="px-6 py-4 bg-gray-50 border-b">
              <div className="h-6 bg-gray-200 rounded w-40 mb-2"></div>
              <div className="h-4 bg-gray-200 rounded w-56"></div>
            </div>
            <div className="p-6">
              <div className="overflow-x-auto">
                <div className="bg-gray-200 rounded-lg">
                  <div className="px-4 py-3 bg-gray-100 border-b">
                    <div className="flex space-x-4">
                      <div className="h-4 bg-gray-300 rounded w-16"></div>
                      <div className="h-4 bg-gray-300 rounded w-24"></div>
                      <div className="h-4 bg-gray-300 rounded w-20"></div>
                      <div className="h-4 bg-gray-300 rounded w-32"></div>
                      <div className="h-4 bg-gray-300 rounded w-16"></div>
                    </div>
                  </div>
                  {[...Array(3)].map((_, i) => (
                    <div key={i} className="px-4 py-3 border-b">
                      <div className="flex space-x-4">
                        <div className="h-8 bg-gray-200 rounded w-16"></div>
                        <div className="h-8 bg-gray-200 rounded w-24"></div>
                        <div className="h-8 bg-gray-200 rounded w-20"></div>
                        <div className="h-8 bg-gray-200 rounded w-32"></div>
                        <div className="h-6 bg-gray-200 rounded w-12"></div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
              
              {/* Action buttons skeleton */}
              <div className="mt-4 flex justify-end items-center space-x-2">
                <div className="h-8 bg-gray-200 rounded w-16"></div>
                <div className="h-8 bg-gray-200 rounded w-24"></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}