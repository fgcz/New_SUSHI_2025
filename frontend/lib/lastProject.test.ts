import { describe, it, expect, beforeEach } from 'vitest';
import { rememberProject, recallProject, chooseLandingProject } from './lastProject';

describe('chooseLandingProject', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  // The reported symptom: every sign-in landed on the lowest-numbered project.
  it('prefers what this browser last looked at over the first project', () => {
    rememberProject(35611);

    expect(chooseLandingProject([1001, 4321, 35611])).toBe(35611);
  });

  it('surviving sign-out is the point, so nothing clears it', () => {
    rememberProject(35611);

    expect(recallProject()).toBe(35611);
  });

  // Legacy SUSHI's users.selected_project, which only legacy writes.
  it("falls back to the value legacy recorded when this browser has none", () => {
    expect(chooseLandingProject([1001, 4321, 35611], 4321)).toBe(4321);
  });

  it('prefers this browser over the recorded value when both are usable', () => {
    rememberProject(35611);

    expect(chooseLandingProject([1001, 4321, 35611], 4321)).toBe(35611);
  });

  it('falls back to the first project when there is nothing to recall', () => {
    expect(chooseLandingProject([1001, 4321], null)).toBe(1001);
  });

  // The awkward case measured on production: masaomi's stored 41161 is not among
  // his 77 LDAP projects, so legacy ignores it too. Honouring it would strand a
  // user on a project they can no longer open.
  it('ignores a remembered project the user is no longer a member of', () => {
    rememberProject(99999);

    expect(chooseLandingProject([1001, 4321], 41161)).toBe(1001);
  });

  it('ignores a negative recorded value, which is legacy\'s "unset" (-1)', () => {
    expect(chooseLandingProject([1001, 4321], -1)).toBe(1001);
  });

  it('returns undefined when the user has no projects at all', () => {
    expect(chooseLandingProject([], 4321)).toBeUndefined();
  });
});
