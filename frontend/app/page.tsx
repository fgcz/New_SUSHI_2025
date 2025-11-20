"use client";

// New landing page component that redirects
export default function Home() {
  const { useRouter } = require("next/navigation");
  const { useEffect } = require("react");
  const router = useRouter();

  useEffect(() => {
    // Redirect to default project
    router.replace("/projects/1001");
  }, [router]);

  // Show loading screen during redirect
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="text-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto"></div>
        <p className="mt-2 text-gray-600">Redirecting to project...</p>
      </div>
    </div>
  );
}
