-- Migration: Drop sushi_applications table
-- Reason: App definitions are now handled by Python sushi_apps registry (in-memory)
-- Date: 2025-05-05
--
-- The sushi_applications table was used by Ruby SUSHI to cache app metadata.
-- Python backend now uses the sushi_apps module with auto-discovery at startup.

-- Safety check: verify table exists before dropping
DROP TABLE IF EXISTS sushi_applications;
