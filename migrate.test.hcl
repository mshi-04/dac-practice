test "migrate" "latest_schema_applies" {
  migrate {
    to = "__LATEST_MIGRATION__"
  }
}
