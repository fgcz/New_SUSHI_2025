export interface Project { 
  number: number;
}

export interface UserProjectsResponse {
  projects: Project[];
  current_user: string;
  // The project this user last chose, read from legacy SUSHI's
  // `users.selected_project`. null when there is none, or when the user is no
  // longer a member of the one recorded.
  selected_project?: number | null;
}
