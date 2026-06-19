env "local" {
  src = "file://schema.sql"
  url = "postgres://app:app_password@localhost:5432/appdb?search_path=public&sslmode=disable"
  dev = "docker://postgres/16/dev?search_path=public"

  migration {
    dir = "file://migrations"
  }
}
