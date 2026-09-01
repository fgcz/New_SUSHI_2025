// Where "the project I was last looking at" lives, and how a landing destination
// is chosen from it.
//
// Legacy SUSHI stores this per USER in `users.selected_project` and writes it on
// every selection. We cannot write it: on the production node this backend shares
// the live legacy database under a read-only policy. So the two halves are split —
// the backend READS legacy's column (which legacy keeps up to date), and a choice
// made in THIS UI is remembered in the browser instead.
//
// The consequences of that split, stated plainly: the browser's memory is
// per-browser and is not shared with legacy SUSHI, and a project chosen here is not
// visible to legacy. Both are accepted; the alternative was widening the production
// write surface for a convenience feature.

const KEY = 'last_project';

export function rememberProject(projectNumber: number): void {
  if (typeof window === 'undefined' || !Number.isFinite(projectNumber)) return;
  try {
    localStorage.setItem(KEY, String(projectNumber));
  } catch {
    // Private mode, quota, storage disabled — remembering is a convenience, never
    // a reason to break the page the user is on.
  }
}

export function recallProject(): number | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const n = Number(raw);
    return Number.isInteger(n) && n >= 0 ? n : null;
  } catch {
    return null;
  }
}

// Deliberately NOT cleared on sign-out: surviving sign-out is the whole request.
// A different user on the same browser inherits nothing usable, because
// chooseLandingProject only accepts a project they are themselves a member of.

/**
 * Which project to open on the landing page.
 *
 * Order, most specific first:
 *   1. what this browser last looked at,
 *   2. what legacy SUSHI recorded for this user (`users.selected_project`),
 *   3. the first project the user may see.
 *
 * A candidate is only used if the user is STILL a member of it — the same rule
 * legacy applies, so losing access to a project cannot strand you on it.
 */
export function chooseLandingProject(
  authorized: number[],
  serverSelected?: number | null,
): number | undefined {
  const allowed = (n: number | null | undefined): n is number =>
    typeof n === 'number' && authorized.includes(n);

  const recalled = recallProject();
  if (allowed(recalled)) return recalled;
  if (allowed(serverSelected)) return serverSelected;

  return authorized[0];
}
