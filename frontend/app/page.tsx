"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo } from "react";
import { useAuth } from "@/providers/AuthContext";
import { useProjectList } from "@/lib/hooks";
import { chooseLandingProject } from "@/lib/lastProject";

// The landing page forwards you into a project. It must not do so before knowing
// WHO you are: AuthContext sends an unauthenticated visitor to /login, and this
// component used to fire `router.replace("/projects/1001")` from a bare mount
// effect, so the two navigations raced and on a node that requires a login the
// login screen never appeared. Waiting for auth removes the race entirely.
//
// The destination was also the hard-coded project 1001, which is simply not
// everyone's project — anyone outside it landed on a 403. It is now the first
// project the API says this user may see.
export default function Home() {
  const router = useRouter();
  const { authStatus, loading: authLoading } = useAuth();
  const { userProjects, isLoading: projectsLoading } = useProjectList();

  // Either signed in, or on a node with authentication switched off.
  const admitted = Boolean(authStatus?.authentication_skipped || authStatus?.current_user);
  const waiting = authLoading || (admitted && projectsLoading);

  // Landing on the LOWEST-numbered project after every sign-in was the complaint.
  // chooseLandingProject prefers what this browser last looked at, then what legacy
  // SUSHI recorded for the user, and only then falls back to the first.
  const authorized = useMemo(
    () => (userProjects?.projects ?? []).map((p) => p.number),
    [userProjects],
  );
  const destination = useMemo(
    () => (waiting ? undefined : chooseLandingProject(authorized, userProjects?.selected_project)),
    [waiting, authorized, userProjects],
  );

  useEffect(() => {
    if (waiting || !admitted) return;
    if (destination !== undefined) {
      router.replace(`/projects/${destination}`);
    }
  }, [waiting, admitted, destination, router]);

  if (admitted && !waiting && destination === undefined) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <p className="text-gray-600">
          No projects are available for this account.
        </p>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="text-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600 mx-auto"></div>
        <p className="mt-2 text-gray-600">
          {admitted ? "Redirecting to project..." : "Checking sign-in..."}
        </p>
      </div>
    </div>
  );
}
