# Backend API Endpoints

This document lists all available REST API endpoints in the backend application.

## Base URL
All endpoints are prefixed with `/api/v1/`

## Authentication
Most endpoints require JWT authentication via the `Authorization: Bearer <token>` header, except where noted as "Public".

---

## Authentication Endpoints

### POST /api/v1/auth/login
**Public** - JWT login with LDAP support
- **Body**: `{ "login": "username", "password": "password" }`
- **Response**: `{ "token": "jwt_token", "user": {...}, "message": "Login successful" }`

### POST /api/v1/auth/register  
**Public** - User registration
- **Body**: `{ "login": "username", "email": "email", "password": "password", "password_confirmation": "password" }`
- **Response**: `{ "token": "jwt_token", "user": {...}, "message": "Registration successful" }`

### POST /api/v1/auth/logout
**Public** - JWT logout (client-side token removal)
- **Response**: `{ "message": "Logout successful" }`

### GET /api/v1/auth/verify
**Public** - Verify JWT token validity
- **Headers**: `Authorization: Bearer <token>`
- **Response**: `{ "user": {...}, "valid": true }`

---

## Projects Endpoints

### GET /api/v1/projects
List accessible projects for current user
- **Response**: `{ "projects": [{"number": 1001}], "current_user": "username" }`

### GET /api/v1/projects/:project_number/datasets
Get datasets under a project with pagination and search
- **Query Params**: `page`, `per`, `q` (search)
- **Response**: `{ "datasets": [...], "total_count": 50, "page": 1, "per": 25, "project_number": 1001 }`

### GET /api/v1/projects/:project_number/datasets/tree
Get tree structure of datasets for a project
- **Response**: `{ "tree": [...], "project_number": 1001 }`

### GET /api/v1/projects/:project_number/jobs
Get jobs for a project with pagination and filtering
- **Query Params**: `page`, `per`, `status`, `user`, `dataset_id`, `from_date`, `to_date`
- **Response**: `{ "jobs": [...], "total_count": 100, "page": 1, "per": 25, "project_number": 1001, "filters": {...} }`

---

## Datasets Endpoints

### GET /api/v1/datasets
List all datasets (or user's datasets if authenticated)
- **Response**: `{ "datasets": [...], "total_count": 25, "current_user": "username" }`

### GET /api/v1/datasets/:id
Get detailed dataset information
- **Response**: Complete dataset details including samples, headers, and runnable applications

### POST /api/v1/datasets
Create a new dataset
- **Body**: `{ "dataset": { "name": "Dataset Name" } }`
- **Response**: `{ "dataset": {...}, "message": "Dataset created successfully" }`

### GET /api/v1/datasets/:id/tree
Get parent tree to root and all children recursively
- **Response**: Array of tree nodes with parent-child relationships

### GET /api/v1/datasets/:id/runnable_apps
Get runnable applications grouped by category
- **Response**: `[{ "category": "Analysis", "applications": ["AppName1", "AppName2"] }]`

### GET /api/v1/datasets/:id/samples
Get all samples in the dataset
- **Response**: Array of sample data objects

---

## Jobs Endpoints

### POST /api/v1/jobs
Submit a new job for processing
- **Body**: 
  ```json
  {
    "job": {
      "dataset_id": 123,
      "app_name": "ApplicationName",
      "parameters": { "param1": "value1" },
      "next_dataset_name": "Output Dataset",
      "next_dataset_comment": "Processing results"
    }
  }
  ```
- **Response**: `{ "job": {...}, "output_dataset": {...}, "message": "Job submitted successfully" }`

### GET /api/v1/jobs/:id
Get job details
- **Response**: `{ "job": {...} }` with detailed job information

### GET /api/v1/jobs
List jobs with optional filtering and pagination
- **Query Params**: `status`, `user`, `page`, `per`
- **Response**: `{ "jobs": [...], "total_count": 50, "page": 1, "per": 25 }`

---

## Application Configuration Endpoints

### GET /api/v1/application_configs
List all available applications
- **Response**: `{ "applications": [{"name": "AppName"}], "total_count": 10 }`

### GET /api/v1/application_configs/:app_name
Get configuration for a specific application
- **Response**: `{ "application": { "name": "...", "class_name": "...", "form_fields": [...] } }`

---

## Authentication Configuration Endpoints

### GET /api/v1/authentication_config
Get current authentication configuration
- **Response**: Configuration for standard login, OAuth2, 2FA, LDAP, and wallet authentication

### PUT /api/v1/authentication_config
**Admin Only** - Update authentication configuration
- **Response**: `{ "message": "Configuration updated successfully" }`

---

## Test Endpoints

### GET /api/v1/hello
**Public** - Simple health check endpoint
- **Response**: `{ "message": "Hello, World!" }`

### GET /api/v1/test/protected
Protected endpoint requiring JWT authentication
- **Response**: `{ "message": "This is a protected endpoint", "current_user": "username", "jwt_authenticated": true }`

### GET /api/v1/test/user_info
Get current user information with JWT validation
- **Response**: `{ "user": {...}, "authentication_method": "JWT", "token_valid": true }`

---

## Error Responses

All endpoints may return standard HTTP error responses:

- **400 Bad Request** - Invalid request parameters
- **401 Unauthorized** - Authentication required or invalid token
- **403 Forbidden** - Insufficient permissions
- **404 Not Found** - Resource not found
- **422 Unprocessable Entity** - Validation errors
- **500 Internal Server Error** - Server error

Error response format:
```json
{
  "error": "Error message",
  "message": "Detailed error description"
}
```

## Authentication Notes

1. **JWT Token**: Include in header as `Authorization: Bearer <token>`
2. **Token Expiration**: Tokens have an expiration time set by server configuration
3. **LDAP Support**: Login endpoint supports both LDAP and standard authentication
4. **Admin Endpoints**: Some endpoints require admin privileges
5. **Project Access**: Users can only access projects they have permission for