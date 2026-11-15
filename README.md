
# Keshav AI Voice KhataBook

Digital customer accounting for Keshav Dairy & Beverages. This monorepo contains the Django REST API and Flutter Android application, including the Gemini-powered voice proposal workflow.

## Current scope

- Django REST Framework backend with customer, catalog, khata, authentication, and voice APIs.
- Flutter Android app with customer, dashboard, manual Khata, and voice entry features.
- Voice entries create a draft and preview; a user must confirm before the existing Khata service posts it.
- Database: MariaDB provided by XAMPP, configured with environment variables.
- Phase 6 migrations are generated but have not been applied to the MariaDB business database. Review `docs/voice-ai.md` before applying them.

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
- `mobile/`: Flutter Android application, organized by feature.

See [docs/database-design.md](docs/database-design.md) for the proposed tables, relationships, ledger rules, and deletion policy.

# Voice AI

Phase 6 voice integration setup, Gemini model/pricing references, endpoint flow, and pending migrations are documented in [docs/voice-ai.md](docs/voice-ai.md).
