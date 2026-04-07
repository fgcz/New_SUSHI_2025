"""LDAP authentication and user lookup."""

from ldap3 import ALL, Connection, Server
from ldap3.core.exceptions import LDAPException

from app.core.config import settings


class LDAPAuthError(Exception):
    """Raised when LDAP authentication fails."""

    pass


class LDAPService:
    """Service for LDAP authentication and user queries."""

    def __init__(self):
        if not settings.SKIP_AUTH:
            self.server = Server(settings.LDAP_HOST, get_info=ALL)

    def authenticate(self, username: str, password: str) -> dict:
        """Authenticate a user against LDAP.

        Args:
            username: The user's login name
            password: The user's password

        Returns:
            Dict with user info: {"login": str, "email": str, "projects": list[int]}

        Raises:
            LDAPAuthError: If authentication fails
        """
        # Skip LDAP and return mock user in development
        if settings.SKIP_AUTH:
            return self._mock_authenticate(username)

        return self._ldap_authenticate(username, password)

    def _mock_authenticate(self, username: str) -> dict:
        """Return mock user data for development.

        Accepts any username, grants access to all projects.
        """
        # Use provided username or default to 'dev_user'
        login = username if username else "dev_user"

        return {
            "login": login,
            "email": f"{login}@local.dev",
            "projects": [],  # Empty means all projects accessible when SKIP_AUTH=True
        }

    def _ldap_authenticate(self, username: str, password: str) -> dict:
        """Authenticate against real LDAP server."""
        # Construct the user DN for binding
        user_dn = f"uid={username},{settings.LDAP_USER_SEARCH_BASE}"

        try:
            # Attempt to bind with user credentials
            conn = Connection(
                self.server,
                user=user_dn,
                password=password,
                auto_bind=True,
            )
        except LDAPException as e:
            raise LDAPAuthError(f"Authentication failed: {e}")

        # Fetch user attributes
        try:
            conn.search(
                search_base=user_dn,
                search_filter="(objectClass=*)",
                attributes=["mail", "uid"],
            )

            if not conn.entries:
                raise LDAPAuthError("User not found after authentication")

            user_entry = conn.entries[0]
            email = str(user_entry.mail) if hasattr(user_entry, "mail") else f"{username}@local"

            # Fetch project memberships
            projects = self._get_user_projects(conn, username)

            return {
                "login": username,
                "email": email,
                "projects": projects,
            }
        finally:
            conn.unbind()

    def _get_user_projects(self, conn: Connection, username: str) -> list[int]:
        """Get project numbers the user has access to.

        Args:
            conn: Active LDAP connection
            username: The user's login name

        Returns:
            List of project numbers
        """
        # Search for groups the user belongs to
        # Assumes groups are named like "project_1234" or have a projectNumber attribute
        conn.search(
            search_base=settings.LDAP_GROUP_SEARCH_BASE,
            search_filter=f"(memberUid={username})",
            attributes=["cn", "gidNumber"],
        )

        projects = []
        for entry in conn.entries:
            cn = str(entry.cn) if hasattr(entry, "cn") else ""
            # Extract project number from group name (e.g., "project_1234")
            if cn.startswith("project_"):
                try:
                    project_num = int(cn.replace("project_", ""))
                    projects.append(project_num)
                except ValueError:
                    pass

        return projects


def get_ldap_service() -> LDAPService:
    """Factory function for LDAP service."""
    return LDAPService()
