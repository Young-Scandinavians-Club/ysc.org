# New Developer Onboarding - Documentation Index

Welcome! This document provides an overview of all the documentation available to help you get started with the YSC development environment.

## Quick Links

### 🚀 Getting Started (Start Here!)
- **[README.md](../README.md)** - Complete setup guide for new developers
  - Prerequisites installation (Docker, Elixir, Stripe CLI, ShellCheck/shfmt)
  - Environment configuration
  - Initial setup and verification
  - Troubleshooting quick fixes

### 📋 Daily Reference
- **[QUICKREF.md](../QUICKREF.md)** - Quick reference guide and cheat sheet
  - Common commands
  - Useful URLs and ports
  - Stripe testing tips
  - Git workflow
  - IEx tips

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
├── README.md                           # Main setup guide (START HERE)
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

1. **Start with [README.md](../README.md)**
   - Follow the setup guide step by step
   - Install prerequisites (Docker, Elixir, Stripe CLI, ShellCheck, shfmt)
   - Configure environment
   - Run initial setup
   - Verify everything works

2. **Bookmark [QUICKREF.md](../QUICKREF.md)**
   - Keep it open while developing
   - Reference common commands
   - Learn keyboard shortcuts and workflows

3. **Skim [DEVELOPMENT_ARCHITECTURE.md](DEVELOPMENT_ARCHITECTURE.md)**
   - Understand how everything connects
   - Learn the technology stack
   - Understand the codebase structure

4. **Keep [TROUBLESHOOTING.md](TROUBLESHOOTING.md) handy**
   - Reference when things go wrong
   - Learn common solutions

### For Experienced Developers

If you're already familiar with Elixir/Phoenix development:

1. **Quick Start** - See the "Quick Start" section in [README.md](../README.md)
2. **Environment Setup** - Copy `.env.example` to `.env` and fill in Stripe keys
3. **Run Setup** - `make dev-setup && make dev`
4. **Architecture** - Skim [DEVELOPMENT_ARCHITECTURE.md](DEVELOPMENT_ARCHITECTURE.md) to understand specifics

## Prerequisites

Before running setup, ensure you have installed:

- **Docker** - For PostgreSQL and LocalStack
- **Elixir/Erlang** (via asdf) - See `.tool-versions` for versions
- **Stripe CLI** - For webhook forwarding during development
- **ShellCheck and shfmt** - For shell script linting (required for `mix precommit` and `make preflight`)

```bash
# macOS
brew install shellcheck shfmt

# Ubuntu/Debian
sudo apt-get install -y shellcheck shfmt
```

See [README.md](../README.md) for complete installation instructions.

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
   - Open http://localhost:8888 (PgAdmin)
   - Connect to database
   - Browse tables

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
