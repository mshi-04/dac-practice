# dac-practice

Database as Code practice project.

This repository uses PostgreSQL and Atlas to practice managing database schema
changes as code.

## Requirements

- Docker
- Docker Compose
- Atlas CLI

## Start the database

```powershell
docker compose up -d db
```

## Apply the desired schema directly

```powershell
atlas schema apply --env local
```

Atlas reads [schema.sql](schema.sql), compares it with the local PostgreSQL
database, plans the change, and asks for approval before applying it.

## Generate a versioned migration

```powershell
atlas migrate diff initial --env local
```

This writes SQL migration files under [migrations](migrations).

## Apply versioned migrations

```powershell
atlas migrate apply --env local
```

## Inspect the database schema

```powershell
atlas schema inspect --url "postgres://app:app_password@localhost:5432/appdb?search_path=public&sslmode=disable" --format "{{ sql . }}"
```

## Connect to PostgreSQL

```powershell
docker compose exec db psql -U app -d appdb
```

## Project Layout

```text
.
├── atlas.hcl
├── docker-compose.yml
├── migrations/
└── schema.sql
```
