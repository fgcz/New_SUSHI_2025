"""Custom exceptions and global exception handlers."""

from fastapi import Request
from fastapi.responses import JSONResponse


class AppException(Exception):
    """Base exception for application errors."""

    def __init__(
        self, message: str, code: str = "UNKNOWN_ERROR", status_code: int = 500
    ):
        self.message = message
        self.code = code
        self.status_code = status_code
        super().__init__(message)


class NotFoundError(AppException):
    """Raised when a requested resource is not found."""

    def __init__(self, resource: str, identifier: any):
        super().__init__(
            message=f"{resource} with id '{identifier}' not found",
            code="NOT_FOUND",
            status_code=404,
        )


class ValidationError(AppException):
    """Raised when input validation fails."""

    def __init__(self, message: str):
        super().__init__(message, "VALIDATION_ERROR", 400)


class DatabaseError(AppException):
    """Raised when a database operation fails."""

    def __init__(self, message: str = "Database operation failed"):
        super().__init__(message, "DATABASE_ERROR", 500)


class AuthenticationError(AppException):
    """Raised when authentication fails."""

    def __init__(self, message: str = "Authentication failed"):
        super().__init__(message, "AUTHENTICATION_ERROR", 401)


class ForbiddenError(AppException):
    """Raised when user lacks permission for an action."""

    def __init__(self, message: str = "Access denied"):
        super().__init__(message, "FORBIDDEN", 403)


class ConflictError(AppException):
    """Raised when a resource conflict occurs (e.g., duplicate)."""

    def __init__(self, message: str = "Resource conflict"):
        super().__init__(message, "CONFLICT", 409)


async def app_exception_handler(request: Request, exc: AppException) -> JSONResponse:
    """Handle application-specific exceptions."""
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.code, "message": exc.message}},
    )


async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Handle unexpected exceptions."""
    return JSONResponse(
        status_code=500,
        content={
            "error": {"code": "INTERNAL_ERROR", "message": "An unexpected error occurred"}
        },
    )
