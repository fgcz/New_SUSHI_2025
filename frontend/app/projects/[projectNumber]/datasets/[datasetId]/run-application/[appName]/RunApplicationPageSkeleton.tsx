export default function RunApplicationPageSkeleton() {
  return (
    <div className="container mx-auto px-6 py-8">
      <div className="animate-pulse">
        {/* Breadcrumb skeleton */}
        <div className="h-4 bg-gray-200 rounded w-64 mb-6"></div>

        {/* Title skeleton */}
        <div className="h-8 bg-gray-200 rounded w-96 mb-6"></div>

        {/* Form skeleton */}
        <div className="bg-white border rounded-lg p-6">
          <div className="space-y-6">
            <div className="h-6 bg-gray-200 rounded w-32 mb-4"></div>
            {[...Array(4)].map((_, i) => (
              <div key={i} className="space-y-2">
                <div className="h-4 bg-gray-200 rounded w-24"></div>
                <div className="h-10 bg-gray-200 rounded"></div>
              </div>
            ))}
            <div className="h-10 bg-gray-200 rounded w-32"></div>
          </div>
        </div>
      </div>
    </div>
  );
}