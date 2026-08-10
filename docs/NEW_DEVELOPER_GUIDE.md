# New Developer Onboarding - Documentation Index

Welcome! This document provides an overview of all the documentation available to help you get started with the YSC development environment.

## Quick Links

### 🚀 Getting Started (Start Here!)
- **[README.md](../README.md)** - Project overview and condensed setup
- **This guide** - Detailed prerequisites, env vars, and local dev workflows (below)

### 📋 Daily Reference
- **[QUICKREF.md](../QUICKREF.md)** - Quick reference guide and cheat sheet
  - Common commands
  - Useful URLs and ports
  - Stripe testing tips
  - Git workflow
  - IEx tips
- **[EMAIL_TESTING_GUIDE.md](EMAIL_TESTING_GUIDE.md)** - Preview email & SMS templates
  - `/dev/notifications` catalog and `/dev/mailbox`
  - Sample data + `mix lint_notification_samples`
  - PR screenshot CI

### 🔀 Contributing
- **[LIFE_OF_A_CHANGESET.md](LIFE_OF_A_CHANGESET.md)** - How to contribute in detail
  - Branch naming: `YOUR_NAME/NAME_OF_YOUR_CHANGE`
  - Open PR against `main`, wait for checks, request review, merge

### 🔧 Troubleshooting
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Comprehensive troubleshooting guide
  - Installation issues
  - Docker issues
  - Database issues
  - Stripe issues
  - Phoenix server issues
  - Compilation and test issues

### 📐 Architecture
- **[DEVELOPMENT_ARCHITECTURE.md](DEVELOPMENT_ARCHITECTURE.md)** - System architecture overview
  - Visual architecture diagrams
  - Data flow examples
  - Port reference
  - Technology stack
  - Codebase structure

## Documentation Organization

```
ysc-redesign-ex/
├── README.md                           # Overview & quick setup (START HERE)
├── QUICKREF.md                         # Daily reference cheat sheet
├── .env.example                        # Template for environment variables
│
├── docs/
│   ├── TROUBLESHOOTING.md              # Detailed troubleshooting
│   ├── DEVELOPMENT_ARCHITECTURE.md     # System architecture
│   ├── SEED_DATA_REFERENCE.md          # Complete seed data reference
│   │
│   └── [other project docs]/           # Additional documentation
│       ├── LEDGER_SYSTEM_README.md
│       ├── TICKET_SYSTEM_README.md
│       ├── RECONCILIATION_SYSTEM.md
│       └── ...
│
└── [project files]
```

## Recommended Reading Order

### For Brand New Developers

1. **Start with [README.md](../README.md)** — run `make dev-setup` and `make dev`
2. **Use this guide** for OS-specific installs, env vars, email/QuickBooks testing
3. **Bookmark [QUICKREF.md](../QUICKREF.md)** for daily commands
4. **Skim [DEVELOPMENT_ARCHITECTURE.md](DEVELOPMENT_ARCHITECTURE.md)** for stack and codebase layout
5. **Keep [TROUBLESHOOTING.md](TROUBLESHOOTING.md) handy**
   - Reference when things go wrong
   - Learn common solutions

### For Experienced Developers

If you're already familiar with Elixir/Phoenix development:

1. **Quick Start** - See the "Quick Start" section in [README.md](../README.md)
2. **Environment Setup** - Copy `.env.example` to `.env` and fill in Stripe keys
3. **Run Setup** - `make dev-setup && make dev`
4. **Architecture** - Skim [DEVELOPMENT_ARCHITECTURE.md](DEVELOPMENT_ARCHITECTURE.md) to understand specifics

## Detailed prerequisites

Install these before `make dev-setup`. Versions for Elixir/Erlang are pinned in `.tool-versions`.

### Docker

**macOS:** [Docker Desktop](https://www.docker.com/products/docker-desktop) or `brew install --cask docker`

**Linux (Ubuntu/Debian):**

```bash
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
sudo usermod -aG docker $USER && newgrp docker
sudo apt-get install docker-compose-plugin
```

Verify: `docker --version` and `docker compose version`

### Elixir & Erlang (asdf)

**macOS:**

```bash
brew install asdf
echo -e "\n. $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.zshrc && source ~/.zshrc
asdf plugin add erlang && asdf plugin add elixir
cd /path/to/ysc-redesign-ex && asdf install
```

**Linux:**

```bash
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc && source ~/.bashrc
# Erlang build deps (Ubuntu): build-essential autoconf m4 libncurses5-dev ...
asdf plugin add erlang && asdf plugin add elixir
cd /path/to/ysc-redesign-ex && asdf install
```

Verify: `elixir --version`

### Stripe CLI

```bash
# macOS
brew install stripe/stripe-cli/stripe

# Linux — see https://github.com/stripe/stripe-cli/releases
stripe login
stripe listen --forward-to localhost:4000/webhooks/stripe
# Copy the whsec_... secret into .env as STRIPE_WEBHOOK_SECRET
```

API keys (test mode): [Stripe Dashboard → API keys](https://dashboard.stripe.com/test/apikeys)

### ShellCheck, shfmt & dprint

Required for `make preflight`:

```bash
# macOS
brew install shellcheck shfmt dprint

# Ubuntu/Debian
sudo apt-get install -y shellcheck shfmt
curl -fsSL https://dprint.dev/install.sh | sh
```

`dprint` formats JSON, YAML, and TOML config files (see `dprint.json`).

## Environment variables

Copy `.env.example` to `.env`. **Required for `make dev`:**

| Variable | Source |
| --- | --- |
| `STRIPE_SECRET` | Dashboard secret key (`sk_test_...`) |
| `STRIPE_PUBLIC_KEY` | Dashboard publishable key (`pk_test_...`) |
| `STRIPE_WEBHOOK_SECRET` | Output of `stripe listen` (`whsec_...`) |

**Optional** (defaults work for most local dev):

- `RADAR_PUBLIC_KEY` — maps (defaults to test key)
- `EMAIL_*` — sender addresses (see `.env.example`)
- `QUICKBOOKS_*` — only if testing accounting sync (see [Optional integrations](#optional-integrations))

Exported shell vars override `.env`. Never commit `.env`.

## Email in development

Emails are **not** sent externally in development. You have two preview tools:

| Tool | URL | When to use |
|------|-----|-------------|
| **Notification catalog** | http://localhost:4000/dev/notifications | Review every email/SMS template with sample data (no app flow needed) |
| **Swoosh mailbox** | http://localhost:4000/dev/mailbox | Inspect emails actually sent by workers/controllers |

Adapter: `Swoosh.Adapters.Local`. Mailbox contents clear when the server restarts.

**Sample assigns** live in `priv/dev/notification_preview_samples.exs`. After changing a template, update that file and run `mix lint_notification_samples` (also in `mix precommit`).

Full guide: [EMAIL_TESTING_GUIDE.md](EMAIL_TESTING_GUIDE.md).

## Newsletter (IEx)

Subscription state only (no campaign sending):

```elixir
Ysc.Newsletter.subscribe("test@example.com", source: "public_signup")
Ysc.Newsletter.get_subscriber_by_email("test@example.com")
Ysc.Newsletter.unsubscribe("test@example.com")
```

Public unsubscribe: `/newsletter/unsubscribe/:token`

## Optional integrations

### QuickBooks (sandbox)

1. [Intuit Developer](https://developer.intuit.com/) — create sandbox app and company
2. Add credentials from `.env.example` (all `QUICKBOOKS_*` vars)
3. Create a payment in the app; monitor sync in Oban at `/admin/settings`

See also [QUICKBOOKS_SYNC_DESIGN.md](QUICKBOOKS_SYNC_DESIGN.md).

## Essential Commands

```bash
# First time setup
make dev-setup

# Daily development
stripe listen --forward-to localhost:4000/webhooks/stripe  # Terminal 1
make dev                                                     # Terminal 2

# Before committing
make preflight

# Get help
make help
```

## Default Login Credentials

After running `make dev-setup`, you can immediately log in:

**Email**: `admin@ysc.org`  
**Password**: `very_secure_password`

See [SEED_DATA_REFERENCE.md](SEED_DATA_REFERENCE.md) for complete details on all seeded test data (users, events, posts, etc.).

## Support Resources

### Documentation
- **Project Documentation**: All files in `docs/` folder
- **Phoenix Framework**: https://hexdocs.pm/phoenix
- **Elixir Language**: https://hexdocs.pm/elixir
- **Stripe API**: https://stripe.com/docs

### Getting Help
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) first
2. Search the codebase for similar patterns
3. Ask your team members
4. Consult external resources (Phoenix forum, Elixir forum)

## Key Concepts

### What You Need to Know

#### Elixir
- Functional programming language
- Runs on the Erlang VM (BEAM)
- Excellent for concurrent, fault-tolerant systems

#### Phoenix
- Web framework for Elixir (like Rails for Ruby)
- Uses LiveView for real-time, server-rendered UI
- Convention over configuration

#### LiveView
- Real-time UI without writing JavaScript
- Server-rendered, WebSocket-connected
- Automatic updates when state changes

#### Ecto
- Database wrapper and query language
- Similar to ActiveRecord but more explicit
- Uses schemas and changesets

#### Docker
- Containerizes dependencies (PostgreSQL, S3, etc.)
- Ensures consistent environment across machines
- Started automatically by `make dev-setup`

#### Stripe
- Payment processing
- Test mode for development
- Webhooks for event notifications

### Important Patterns

1. **Context Pattern**: Business logic grouped in contexts (`lib/ysc/`)
2. **Separation of Concerns**: Web layer (`lib/ysc_web/`) separate from business logic
3. **Background Jobs**: Long-running tasks use Oban workers
4. **Immutability**: Elixir variables are immutable (but can be rebound)

## Common Tasks

### Making Changes

```bash
# 1. Create a branch
git checkout -b feature/my-feature

# 2. Make changes in lib/
# Phoenix auto-reloads most changes

# 3. Write tests in test/
make test

# 4. Run preflight before committing
make preflight

# 5. Commit and push
git add .
git commit -m "Add my feature"
git push -u origin feature/my-feature
```

### Running Tests

```bash
make test              # All tests
make test-failed       # Only failed tests
mix test test/path/to/specific_test.exs  # Specific file
```

### Database Operations

```bash
make reset-db          # Drop database
make setup-dev-db      # Create, migrate, seed
mix ecto.migrate       # Run migrations
mix ecto.rollback      # Rollback last migration
```

### Debugging

```elixir
# Add to your code
require IEx; IEx.pry()

# Then run
make dev
# or
make shell
```

## Best Practices

1. **Always run `make preflight` before committing**
2. **Keep Stripe CLI running** during development
3. **Use `make clean` if things get weird**
4. **Write tests for new features**
5. **Follow the existing code style**
6. **Ask questions early** - your team is here to help!

## What's Next?

After completing the setup:

1. ✅ **Verify setup** - Make sure http://localhost:4000 works
2. ✅ **Run tests** - Ensure `make test` passes
3. ✅ **Explore code** - Look around `lib/ysc_web/live/` for examples
4. ✅ **Make a small change** - Try modifying a LiveView template
5. ✅ **Read project docs** - Check out other files in `docs/`

## Quick Wins for Your First Day

Try these to get familiar with the system:

1. **Change homepage text**
   - Edit `lib/ysc_web/controllers/page_html/home.html.heex`
   - Save and refresh browser
   - See LiveReload in action

2. **Inspect database**
   - `docker compose -f etc/docker/docker-compose.yml exec postgres psql -U postgres -d ysc_dev`
   - Or `make shell` and query via `Ysc.Repo`

3. **Run IEx shell**
   - Run `make shell`
   - Try: `Ysc.Repo.aggregate(Ysc.Accounts.User, :count)`
   - Explore the data

4. **Create a test payment**
   - Use card `4242 4242 4242 4242`
   - Watch Stripe CLI show webhook events
   - Check logs in Phoenix terminal

## Remember

- **Documentation is your friend** - Reference these guides often
- **It's okay to not know everything** - This is a learning process
- **Break things in development** - That's what it's for!
- **Ask for help** - Your team wants you to succeed

Happy coding! 🚀
