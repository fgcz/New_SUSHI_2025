# Environment-Specific Notes

This document records environment-specific dependencies and considerations for the SUSHI application.

## SLURM Cluster Dependency

### Overview
The job submission system assumes a SLURM cluster environment is available.

### Affected Components
- `backend/app/helpers/sushi_config_helper.rb` - Fetches partitions via `sinfo` command
- `backend/config/sushi.yml` - Partition configuration
- `backend/lib/sushi_fabric.rb` - Uses partition for job scripts

### SLURM Commands Used
```bash
sinfo --format=%R  # Get available partitions
```

### For Non-SLURM Environments
If deploying to an environment without SLURM:

1. **Disable dynamic partition fetching** in `config/sushi.yml`:
   ```yaml
   development:
     partition:
       default: default
       available: [default]
       dynamic: false
   ```

2. **Or implement alternative scheduler support**:
   - Create a new helper similar to `SushiConfigHelper`
   - Modify `sushi_fabric.rb` to generate scripts for the target scheduler
   - Update job_manager to work with the new scheduler

### Related Configuration
- `SUSHI_TYPE` environment variable: Controls production deployment type
- Options: `production`, `demo`, `course`, `test_server`

## Job Manager Integration

### Overview
The external job_manager expects specific files and formats.

### Required Files
- `parameters.tsv` - Located at `dirname(dirname(script_path))`
- Must contain: `cores`, `ram`, `scratch`, `partition`

### Job Manager Location
- Not part of this repository
- Located at: `/srv/sushi/job_manager_by_masa/` (on FGCZ servers)

## Legacy Database Mode

### Overview
For connecting to old SUSHI MySQL database that lacks email/password columns.
This mode allows the new SUSHI frontend to work with the existing production database.

### Usage

Start the development server with legacy database mode:
```bash
LEGACY_DATABASE=true bash start-dev.sh
```

Or set the environment variable and run Rails directly:
```bash
cd backend
export LEGACY_DATABASE=true
bundle exec rails server
```

### Configuration

1. **Configure database connection** in `backend/config/database.yml`:
   ```yaml
   development:
     adapter: mysql2
     pool: 10
     username: sushilover
     password: YOUR_PASSWORD
     database: sushi
     encoding: utf8
     socket: /var/run/mysqld/mysqld.sock
     reconnect: true
   ```

2. **Enable legacy mode** in `backend/config/authentication.yml`:
   ```yaml
   development:
     legacy_database:
       enabled: true
   ```

### What It Does
- Skips Devise `:validatable` module (old DB has no email/password columns)
- Disables OAuth2, 2FA, wallet authentication features
- Skips pending migration checks (prevents `ActiveRecord::PendingMigrationError`)
- Uses LDAP authentication only (if enabled)

### Important Warnings

⚠️ **DO NOT run migrations** on the legacy database:
```bash
# NEVER do this with LEGACY_DATABASE=true
bundle exec rails db:migrate  # This will modify the production database!
```

⚠️ **The old database schema is read-only** from this application's perspective.
Any schema changes should be done through the old SUSHI system.

⚠️ **User authentication** is limited in legacy mode:
- Standard email/password login is disabled
- Only LDAP authentication works (if configured)
- Anonymous access works if `skip_authentication: true` is set

### Checking Database Connection

Verify jobs are being registered:
```bash
cd backend
LEGACY_DATABASE=true bundle exec rails runner "puts Job.count; Job.last(5).each { |j| p j.attributes }"
```

### Troubleshooting

1. **PendingMigrationError**: Ensure `LEGACY_DATABASE=true` is set before starting the server
2. **Connection refused**: Check MySQL socket path and credentials
3. **Authentication errors**: Verify `authentication.yml` settings match legacy mode requirements

---

*Last updated: 2025-11-27*

