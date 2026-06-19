# Atlas Database Schema Management

Atlas is a language-independent tool for managing and migrating database schemas using modern DevOps principles.

## Quick Reference

```bash
atlas schema inspect --env <name>
atlas schema validate --env <name>
atlas migrate status --env <name>
atlas migrate diff --env <name>
atlas migrate lint --env <name> --latest 1
atlas migrate apply --env <name>
atlas whoami
```

## Core Concepts and Configurations

### Configuration File Structure
Atlas uses `atlas.hcl` configuration files with the following structure:

```hcl
env "<name>" {
  url = getenv("DATABASE_URL")
  dev = "docker://postgres/15/dev?search_path=public"

  migration {
    dir = "file://migrations"
  }

  schema {
    src = "file://schema.hcl"
  }
}
```

### Dev Database
Atlas uses a temporary "dev-database" to process and validate schemas. The URL format depends on whether the project uses a single schema or multiple schemas:

```
# Schema-scoped (single schema — most common)
--dev-url "docker://mysql/8/dev"
--dev-url "docker://postgres/15/dev?search_path=public"
--dev-url "sqlite://dev?mode=memory"
--dev-url "docker://sqlserver/2022-latest/dev?mode=schema"

# Database-scoped (multiple schemas, extensions, or event triggers)
--dev-url "docker://mysql/8"
--dev-url "docker://postgres/15/dev"
--dev-url "docker://sqlserver/2022-latest/dev?mode=database"

# PostGIS / pgvector
--dev-url "docker://postgis/latest/dev?search_path=public"
--dev-url "docker://pgvector/pg17/dev?search_path=public"
```

**Important:** Using the wrong scope causes errors (`ModifySchema is not allowed`) or silently drops database-level objects from migrations. Match the dev URL scope to the project's target database URL.

See https://atlasgo.io/concepts/dev-database for additional drivers and options.

### Environment Variables and Security

**DO**: Use secure configuration patterns
```hcl
// Using environment variables (recommended)
env "<name>" {
  url = getenv("DATABASE_URL")
}

// Using external data sources
data "external" "envfile" {
  program = ["npm", "run", "envfile.js"]
}

locals {
  envfile = jsondecode(data.external.envfile)
}

env "<name>" {
  url = local.envfile.DATABASE_URL
}
```

**DON'T**: Hardcode sensitive values
```hcl
// Never do this
env "prod" {
  url = "postgres://user:password123@prod-host:5432/database"
}
```

### Schema Sources

#### HCL Schema
```hcl
data "hcl_schema" "<name>" {
  path = "schema.hcl"
}

env "<name>" {
  schema {
    src = data.hcl_schema.<name>.url
  }
}
```

#### External Schema (ORM Integration)
The `external_schema` data source imports SQL schema from an external program.

```hcl
data "external_schema" "drizzle" {
  program = ["npx", "drizzle-kit", "export"]
}

data "external_schema" "django" {
  program = ["python", "manage.py", "atlas-provider-django", "--dialect", "postgresql"]
}

env "<name>" {
  schema {
    src = data.external_schema.django.url
  }
}
```

**Important:** The output must be a complete SQL schema (not a diff). If errors occur, run the program directly to isolate the issue.

#### Composite Schema (Pro)
Combine multiple schemas into one. Requires `atlas login`.

```hcl
data "composite_schema" "app" {
  schema "users" {
    url = data.external_schema.auth_service.url
  }
  schema "graph" {
    url = "ent://ent/schema"
  }
}

env "<name>" {
  schema {
    src = data.composite_schema.app.url
  }
}
```

## Common Workflows

### 1. Schema Inspection / Visualization

1. Start by listing tables — don't inspect the entire schema at once for large databases.
2. Default output is HCL. Use `--format "{{ json . }}"` for JSON or `--format "{{ sql . }}"` for SQL.
3. Use `--include`/`--exclude` to filter specific tables or objects.

**Inspect the environment's schema source (`env://src`):**
```bash
atlas schema inspect --env <name> --url "env://src" --format "{{ sql . }}"
atlas schema inspect --env <name> --url "env://src" --format "{{ json . }}" | jq ".schemas[].tables[].name"
```

**Inspect the environment's target database:**
```bash
atlas schema inspect --env <name> --format "{{ sql . }}"
atlas schema inspect --env <name> --include "users" --format "{{ sql . }}"
```

**Inspect migration directory:**
```bash
atlas schema inspect --env <name> --url file://migrations --format "{{ sql . }}"
```

Add `-w` to open a web-based ERD visualization (requires `atlas login`).

### 2. Migration Status

Compare applied migrations against the migrations directory. Only use when you know the target database.

```bash
atlas migrate status --env <name>
atlas migrate status --dir file://migrations --url <url>
```

### 3. Migration Generation / Diffing

```bash
atlas migrate diff --env <name> "add_user_table"

atlas migrate diff \
  --dir file://migrations \
  --dev-url docker://postgres/15/dev \
  --to file://schema.hcl \
  "add_user_table"
```

**Configuration for migration generation:**
```hcl
env "<name>" {
  dev = "docker://postgres/15/dev?search_path=public"

  migration {
    dir = "file://migrations"
  }

  schema {
    src = "file://schema.hcl"
    # Or: src = data.external_schema.<name>.url
    # Or: src = getenv("DATABASE_URL")
  }
}
```

### 4. Migration Linting

```bash
atlas migrate lint --env <name> --latest 1
atlas migrate lint --env <name> --latest 3
atlas migrate lint --env ci
```

**Linting configuration:**
```hcl
lint {
  destructive {
    error = false  // Allow destructive changes with warnings
  }
}

env "ci" {
  lint {
    git {
      base = "main"
    }
  }
}
```

To suppress a specific lint error, add `-- atlas:nolint` before the SQL statement.

> **Important:** When fixing migration issues:
> - **Unapplied migrations:** Edit the file, then run `atlas migrate hash --env "<name>"`
> - **Applied migrations:** Never edit directly. Create a new corrective migration instead.
> - **Never use `-- atlas:nolint` without properly fixing the issue or getting user approval.**

### 5. Applying Changes

**Versioned (migration files):**
```bash
atlas migrate apply --env <name> --dry-run    # Always preview first
atlas migrate apply --env <name>
```

**Declarative (direct apply — fast local iteration):**
```bash
atlas schema apply --env <name> --dry-run     # Preview changes
atlas schema apply --env <name>               # Apply directly to database
```

Use `schema apply` for fast edit-apply cycles on a local database without generating migration files. Add `--auto-approve` to skip the confirmation prompt during development.

## Troubleshooting

```bash
atlas version
atlas whoami
atlas migrate hash --env <name>
```

**Missing driver error**: Either `--url` or `--dev-url` is missing or incorrect.

## Key Reminders

1. **Always read `atlas.hcl` first** — use environment names from config
2. **Never hardcode database URLs** — use `getenv()` or secure data sources
3. **Run `atlas schema validate`** after editing schema files
4. **Run `atlas migrate hash`** after manually editing migration files
5. **Use `atlas migrate lint`** to validate migrations before applying
6. **Always use `--dry-run`** before applying migrations
7. **Use `--include`/`--exclude`** to filter tables in schema inspection
8. **Never ask for sensitive information** such as passwords or database URLs
9. **Never ignore linting errors** — fix them or get user approval
10. **Inspect schemas at high level first** — schemas might be very large
11. **Only use atlas commands listed here** — other commands may not be supported
12. **Prefer `atlas schema inspect`** over reading migration files directly