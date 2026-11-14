# Keshav AI Voice KhataBook

Digital customer accounting for Keshav Dairy & Beverages. The repository is a monorepo; this initial scaffold contains the Django REST API only. The Flutter application will be added in a later phase.

## Current scope

- Phase 1A scaffold: Django project, REST Framework configuration, domain app packages, and database design notes.
- Database: MariaDB provided by XAMPP, configured with environment variables.
- No database migrations have been created or run as part of this scaffold.

## Backend setup (PowerShell)

From the repository root:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
py -m pip install -r backend\requirements.txt
Copy-Item .env.example .env
```

Edit `.env` with a local Django secret and the MariaDB connection values. Never commit `.env`. `DB_PASSWORD` is deliberately blank in the example; set it to the password configured in your local MariaDB, or leave it blank only if that database account has no password.

Start the XAMPP MariaDB service and create the empty database named by `DB_NAME` (default `keshav_khatabook`). Then, after reviewing the schema and approving migrations, the Django development server can be started with:

```powershell
py backend\manage.py runserver
```

The scaffold does not run migrations. Django's system check and migration commands should be run only after the database settings and model design are reviewed.

## Project layout

- `backend/config/`: Django settings and URL/ASGI/WSGI entry points.
- `backend/apps/`: business-domain Django applications.
- `backend/requirements.txt`: backend Python dependencies.
- `docs/`: architecture and data design.
- `mobile/`: reserved for the future Flutter application; not created in Phase 1A.

See [docs/database-design.md](docs/database-design.md) for the proposed tables, relationships, ledger rules, and deletion policy.
