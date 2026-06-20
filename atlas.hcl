env "local" {
  src = "file://schema.sql"
  url = getenv("DATABASE_URL")
  dev = "docker://postgres/16/dev?search_path=public"

  migration {
    dir = "file://migrations"
  }
}

# CI uses the GitHub Actions PostgreSQL service. Keep it separate from local so
# commands in workflows never depend on a developer's environment variables.
env "ci" {
  src = "file://schema.sql"
  url = getenv("DATABASE_URL")
  dev = "docker://postgres/16/dev?search_path=public"

  migration {
    dir = "file://migrations"
  }
}

# The CodeBuild deployment job supplies DATABASE_URL from AWS Secrets Manager.
# This environment is intentionally used only for status and versioned applies.
env "verification" {
  src = "file://schema.sql"
  url = getenv("DATABASE_URL")
  dev = "docker://postgres/16/dev?search_path=public"

  migration {
    dir = "file://migrations"
  }
}
