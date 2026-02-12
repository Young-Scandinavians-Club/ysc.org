# YSC Development Quick Reference

This is a quick reference guide for common development tasks. For full setup instructions, see [README.md](README.md).

## Daily Development Workflow

### Starting Your Development Session

```bash
# Terminal 1: Start Stripe webhook forwarding
stripe listen --forward-to localhost:4000/webhooks/stripe

# Terminal 2: Start the Phoenix dev server
make dev

# Open your browser
open http://localhost:4000
```

### Default Login Credentials

After running `make dev-setup`, you can log in with the seeded admin account:

**Email**: `admin@ysc.org`
**Password**: `very_secure_password`

Other test users follow the pattern `firstname_lastname_N@ysc.org` (all with the same password).

### Stopping Your Development Session

```bash
# In Terminal 2 (Phoenix server): Press Ctrl+C twice
# In Terminal 1 (Stripe CLI): Press Ctrl+C
```

## Common Commands

### Development Server

```bash
make dev              # Start the Phoenix development server (with automatic checks)
make dev-services     # Start Docker services only (postgres, localstack, etc.)
make shell            # Open an IEx shell with the app loaded
```

**Note:** `make dev` now includes automatic checks for:

- Environment variables (Stripe credentials)
- Docker containers (PostgreSQL, LocalStack)
- Database connection
- Pending migrations

If any check fails, you'll get helpful error messages with fix instructions.

### Testing

```bash
make test             # Run the full test suite
make test-failed      # Run only previously failed tests
```

### Database

```bash
make reset-db         # Drop the local database
make setup-dev-db     # Create, migrate, and seed the database
```

### Code Quality

```bash
make format           # Format all Elixir code
make lint             # Run linting checks (Credo + format check)
make preflight        # Run ALL CI checks locally (recommended before committing)
```

### Docker Services

```bash
# Start all Docker services
docker-compose -f etc/docker/docker-compose.yml up -d

# Stop all Docker services
docker-compose -f etc/docker/docker-compose.yml down

# View logs
docker-compose -f etc/docker/docker-compose.yml logs

# Check status
docker-compose -f etc/docker/docker-compose.yml ps
```

### Clean Slate

```bash
make clean            # Remove Docker containers and build artifacts
make dev-setup        # Set up everything from scratch
```

## Useful URLs

- **Application**: http://localhost:4000
- **Email Preview (Swoosh)**: http://localhost:4000/dev/mailbox
  - View all app emails (registration, notifications, tickets, etc.)
  - Emails stored in memory (cleared on restart)
- **PgAdmin** (Database UI): http://localhost:8888
  - Email: `admin@ysc.org`
  - Password: `password`
- **LocalStack** (Local AWS S3): http://localhost:4566

## Stripe Testing

### Test Card Numbers

- **Success**: `4242 4242 4242 4242`
- **Decline**: `4000 0000 0000 0002`
- **Requires Authentication**: `4000 0025 0000 3155`
- **Expired Card**: Use any past expiration date

Use any future date for expiry, any 3 digits for CVC, and any 5 digits for ZIP.

### Webhook Testing

All webhook events are automatically forwarded to your local server when you run:

```bash
stripe listen --forward-to localhost:4000/webhooks/stripe
```

You can also trigger specific events manually:

```bash
stripe trigger payment_intent.succeeded
stripe trigger customer.subscription.updated
```

## Git Workflow

### Before You Commit

**ALWAYS run preflight checks:**

```bash
make preflight
```

This runs all CI checks locally and will save you time by catching issues before pushing.

### Creating a Pull Request

```bash
# Create a new branch
git checkout -b feature/my-feature

# Make your changes
# ...

# Run preflight checks
make preflight

# Commit your changes
git add .
git commit -m "Add my feature"

# Push and create PR
git push -u origin feature/my-feature
```

## Newsletter Testing

Newsletter subscriptions use the in-house `Ysc.Newsletter` context and `newsletter_subscribers` table.

### Quick Test Flow

```bash
# 1. Make sure dev environment is running
make dev

# 2. Test subscription via homepage
# Visit http://localhost:4000, scroll to newsletter section, enter email

# 3. Unsubscribe page: /newsletter/unsubscribe/:token (token from subscriber record)
```

### Testing in IEx

```elixir
make shell

# Subscribe
Ysc.Newsletter.subscribe("test@example.com", source: "public_signup")

# Get subscriber
Ysc.Newsletter.get_subscriber_by_email("test@example.com")

# Unsubscribe
Ysc.Newsletter.unsubscribe("test@example.com")
```

## Email Testing

### Quick Test Flow

```bash
# 1. Start dev server
make dev

# 2. Trigger an email (e.g., register a user)
# Visit http://localhost:4000/users/register

# 3. View email in Swoosh mailbox
open http://localhost:4000/dev/mailbox
```

### Common Email Tests

**Registration email:**

```bash
# Register at http://localhost:4000/users/register
# Check http://localhost:4000/dev/mailbox
```

**Password reset:**

```bash
# Go to http://localhost:4000/users/reset-password
# Check /dev/mailbox for reset link
```

**Event/Ticket confirmation:**

```bash
# Purchase ticket or register for event
# Check /dev/mailbox for confirmation
```

### Email in development

All app emails (registration, notifications, tickets, etc.) are caught by the Swoosh local adapter and viewable at http://localhost:4000/dev/mailbox.

## Environment Variables

### Required Variables

These must be set in your `.env` file:

```bash
STRIPE_SECRET=sk_test_...
STRIPE_PUBLIC_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

### Getting Stripe Credentials

1. **API Keys**: https://dashboard.stripe.com/test/apikeys
2. **Webhook Secret**: Run `stripe listen --forward-to localhost:4000/webhooks/stripe`

## Troubleshooting Quick Fixes

### "Docker containers not running"

```bash
# Start all Docker services
make dev-services

# Or manually
docker-compose -f etc/docker/docker-compose.yml up -d
```

### "Port 4000 already in use"

```bash
lsof -i :4000  # Find the process
kill -9 <PID>  # Kill it
```

### "Database connection error"

```bash
# Restart PostgreSQL
docker-compose -f etc/docker/docker-compose.yml restart postgres
./etc/scripts/_wait_db_connection.sh

# Or start all services
make dev-services
```

### "Pending migrations"

```bash
# Apply migrations
mix ecto.migrate

# Or reset and rebuild database
make reset-db
make setup-dev-db
```

### "Stripe webhook secret invalid"

1. Make sure `stripe listen` is running
2. Copy the `whsec_...` secret from the Stripe CLI output
3. Update `STRIPE_WEBHOOK_SECRET` in your `.env` file
4. Restart the Phoenix server

### "Everything is broken"

```bash
make clean
make dev-setup
```

## Helpful Make Targets

Run `make help` to see all available commands:

```bash
make help
```

Common targets:

- `make dev` - Start the dev server (with automatic checks)
- `make dev-services` - Start Docker services only
- `make dev-setup` - Set up the development environment
- `make test` - Run tests
- `make format` - Format code
- `make lint` - Run linting
- `make preflight` - Run all CI checks
- `make clean` - Clean up everything
- `make help` - Show all available targets

## IEx (Interactive Elixir) Tips

When you run `make shell`, you get an IEx session. Here are some useful commands:

```elixir
# Reload a module after making changes
r(Ysc.Accounts)

# List all functions in a module
exports Ysc.Accounts

# Get help for a function
h Ysc.Accounts.get_user

# Recompile the project
recompile()

# List all tables in the database
Ysc.Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname='public'")

# Count records in a table
Ysc.Repo.aggregate(Ysc.Accounts.User, :count)
```

## Database Access

### Using PgAdmin

1. Open http://localhost:8888
2. Login: `admin@ysc.org` / `password`
3. Add server:
   - Name: `Local Dev`
   - Host: `postgres` (or `localhost` from host machine)
   - Port: `5432`
   - Database: `ysc_dev`
   - Username: `postgres`
   - Password: `postgres`

### Using psql (Command Line)

```bash
# Connect to the database
docker-compose -f etc/docker/docker-compose.yml exec postgres psql -U postgres -d ysc_dev

# Or from your host machine (if psql is installed)
PGPASSWORD=postgres psql -h localhost -U postgres -d ysc_dev
```

## VS Code / Cursor Setup

### Recommended Extensions

- ElixirLS (official Elixir language server)
- Phoenix Framework (syntax highlighting for templates)
- Tailwind CSS IntelliSense
- Docker

### Workspace Settings

The project already includes recommended settings. If you need to customize, edit `.vscode/settings.json`.

## Need More Help?

- **Troubleshooting guide**: See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for detailed solutions
- **Full setup guide**: See [README.md](README.md)
- **Project documentation**: See `docs/` folder
- **Phoenix docs**: https://hexdocs.pm/phoenix
- **Elixir docs**: https://hexdocs.pm/elixir
- **Stripe docs**: https://stripe.com/docs
