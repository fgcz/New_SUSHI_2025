"""Project service for project-related business logic."""


class ProjectService:
    """Service for project operations."""

    def __init__(self):
        pass

    def get_user_projects(self, user: str) -> dict:
        """Get projects for a user.

        Note: Currently returns mock data. Will be implemented with real
        database queries when project-user relationship is established.
        """
        # Mock implementation - returns project numbers 0-99
        projects: list[int] = list(range(100))

        return {
            "projects": projects,
            "current_user": user,
        }
