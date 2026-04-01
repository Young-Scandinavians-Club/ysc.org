# Troubleshooting Guide

This guide covers common issues you might encounter during development and how to fix them.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Docker Issues](#docker-issues)
- [Database Issues](#database-issues)
- [Stripe Issues](#stripe-issues)
- [Phoenix Server Issues](#phoenix-server-issues)
- [Compilation Issues](#compilation-issues)
- [Test Issues](#test-issues)
- [Getting Help](#getting-help)

## Installation Issues

### asdf: command not found

**Problem**: After installing asdf, the command is not recognized.

**Solution**:

```bash
# Make sure you added asdf to your shell config and reloaded it

# For zsh (macOS default):
echo -e "\n. $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.zshrc
source ~/.zshrc

# For bash:
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
source ~/.bashrc

# Verify it works:
asdf version
```

### Erlang compilation fails on Linux

**Problem**: `asdf install` fails when trying to compile Erlang.

**Solution**: Install required build dependencies:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install build-essential autoconf m4 libncurses5-dev \
  libwxgtk3.0-gtk3-dev libwxgtk-webview3.0-gtk3-dev libgl1-mesa-dev \
  libglu1-mesa-dev libpng-dev libssh-dev unixodbc-dev xsltproc fop \
  libxml2-utils libncurses-dev openjdk-11-jdk

# Try installing again
asdf install
```

### Stripe CLI installation fails

**Problem**: Can't install Stripe CLI via Homebrew on macOS.

**Solution**: Install manually:

```bash
# Download the latest release
curl -LO https://github.com/stripe/stripe-cli/releases/latest/download/stripe_latest_darwin_amd64.tar.gz

# Extract
tar -xvf stripe_latest_darwin_amd64.tar.gz

# Move to PATH
sudo mv stripe /usr/local/bin/

# Verify
stripe --version
```

## Docker Issues

### Docker daemon not running

**Problem**: `docker-compose` commands fail with "Cannot connect to the Docker daemon"

**Solution**:

**macOS**:
```bash
# Open Docker Desktop from Applications folder
open /Applications/Docker.app

# Wait for Docker to start (you'll see the whale icon in the menu bar)
```

**Linux**:
```bash
# Start Docker service
sudo systemctl start docker

# Enable Docker to start on boot
sudo systemctl enable docker

# Verify Docker is running
sudo systemctl status docker
```

### Permission denied when running Docker (Linux)

**Problem**: `docker` commands require `sudo`

**Solution**:

```bash
# Add your user to the docker group
sudo usermod -aG docker $USER

# Apply the new group membership (or log out and back in)
newgrp docker

# Verify you can run docker without sudo
docker ps
```

### Docker containers fail to start

**Problem**: `docker-compose up` fails or containers keep restarting

**Solution**:

```bash
# Check container status and logs
docker-compose -f etc/docker/docker-compose.yml ps
docker-compose -f etc/docker/docker-compose.yml logs

# Try a clean restart
docker-compose -f etc/docker/docker-compose.yml down -v
docker-compose -f etc/docker/docker-compose.yml up -d

# Check if ports are already in use
lsof -i :5432  # PostgreSQL
lsof -i :9000  # MinIO S3 API
lsof -i :9001  # MinIO console
```

### Port conflicts

**Problem**: "Port is already allocated" error

**Solution**:

```bash
# Find what's using the port (e.g., 5432 for PostgreSQL)
lsof -i :5432

# Kill the process
kill -9 <PID>

# Or stop the conflicting container
docker ps
docker stop <container_id>
```

## Database Issues

### Database connection refused

**Problem**: "Connection refused" when trying to connect to PostgreSQL

**Solution**:

```bash
# Quick fix: Start Docker services
make dev-services

# Or manually:
# 1. Make sure PostgreSQL container is running
docker-compose -f etc/docker/docker-compose.yml ps postgres

# 2. If not running, start it
docker-compose -f etc/docker/docker-compose.yml up -d postgres

# 3. Wait for it to be ready
./etc/scripts/_wait_db_connection.sh

# 4. Check the logs if still failing
docker-compose -f etc/docker/docker-compose.yml logs postgres
```

**Note**: The `make dev` command now automatically checks if PostgreSQL is running and will give you a helpful error message if it's not.

### Database doesn't exist

**Problem**: "database 'ysc_dev' does not exist"

**Solution**:

```bash
# Create and set up the database
make setup-dev-db
```

### Migration errors

**Problem**: Migrations fail or are out of sync

**Solution**:

```bash
# 1. Check migration status
mix ecto.migrations

# 2. Apply pending migrations
mix ecto.migrate

# 3. If needed, reset the database (WARNING: destroys all data)
make reset-db
make setup-dev-db

# 4. If only specific migrations failed, try rolling back
mix ecto.rollback
mix ecto.migrate
```

**Note**: The `make dev` command now checks for pending migrations and will warn you if any haven't been applied.

### "Too many connections" error

**Problem**: PostgreSQL refuses connections due to too many open connections

**Solution**:

```bash
# Restart PostgreSQL container
docker-compose -f etc/docker/docker-compose.yml restart postgres

# If you have IEx sessions open, close them
# They hold database connections
```

## Stripe Issues

### Stripe webhook secret invalid

**Problem**: "Invalid signature" errors in logs

**Solution**:

```bash
# 1. Make sure Stripe CLI is running
stripe listen --forward-to localhost:4000/webhooks/stripe

# 2. Copy the webhook secret from the output (starts with whsec_)

# 3. Update your .env file with the new secret
nano .env
# Update STRIPE_WEBHOOK_SECRET=whsec_...

# 4. Restart the Phoenix server
# Press Ctrl+C twice, then run: make dev
```

### Stripe CLI not forwarding events

**Problem**: Webhook events aren't reaching your local server

**Solution**:

```bash
# 1. Make sure you're logged in
stripe login

# 2. Start forwarding in the foreground to see errors
stripe listen --forward-to localhost:4000/webhooks/stripe

# 3. Test with a trigger
stripe trigger payment_intent.succeeded

# 4. Check if your Phoenix server is running and accessible
curl http://localhost:4000
```

### Stripe API keys not working

**Problem**: "Invalid API key" errors

**Solution**:

1. Make sure you're using **Test Mode** keys from https://dashboard.stripe.com/test/apikeys
2. Test mode keys start with `sk_test_` and `pk_test_`
3. Verify your `.env` file has the correct keys
4. Restart the Phoenix server after updating `.env`

## Phoenix Server Issues

### Automatic Checks (New!)

As of the latest update, the `make dev` command now performs automatic checks before starting the Phoenix server:

- ✅ Environment variables (Stripe credentials)
- ✅ Docker containers (PostgreSQL, MinIO)
- ✅ Database connection
- ✅ Pending migrations

If any check fails, you'll get a clear error message with instructions on how to fix it. This helps catch common issues before they cause problems.

**Example helpful error:**
```
✗ PostgreSQL container is not running
  Hint: Start containers with: docker-compose -f etc/docker/docker-compose.yml up -d
  Or run: make dev-setup
```

### Port 4000 already in use

**Problem**: "Address already in use" when starting the server

**Solution**:

```bash
# Find what's using port 4000
lsof -i :4000

# Kill the process
kill -9 <PID>

# Or use a different port
echo "PORT=4001" >> .env
make dev
# Visit http://localhost:4001 instead
```

### Server crashes on startup

**Problem**: Phoenix server starts but immediately crashes

**Solution**:

```bash
# 1. Check for environment variable issues
cat .env
# Make sure all required vars are set

# 2. Check for compilation errors
mix compile

# 3. Check dependencies
mix deps.get
mix deps.compile

# 4. Look at the error logs carefully
# They usually indicate what's wrong
```

### Assets not loading

**Problem**: CSS/JS files not loading, styling looks broken

**Solution**:

```bash
# 1. Install Node dependencies
cd assets
npm install
cd ..

# 2. Rebuild assets
mix assets.deploy

# 3. Restart the server
# Press Ctrl+C twice, then: make dev
```

### LiveView disconnects frequently

**Problem**: "LiveView disconnected" messages in browser console

**Solution**:

1. Check your browser console for specific errors
2. Make sure your `.env` has correct Stripe keys
3. Check for errors in the Phoenix server logs
4. Try a hard refresh (Cmd+Shift+R on Mac, Ctrl+Shift+R on Linux)

## Compilation Issues

### "warnings as errors" failing preflight

**Problem**: `make preflight` fails on warnings

**Solution**:

```bash
# See the warnings
mix compile --warnings-as-errors

# Fix each warning
# Common issues:
# - Unused variables (prefix with _ or remove)
# - Unused aliases or imports (remove them)
# - Deprecated function calls (update to new API)
```

### Dependency conflicts

**Problem**: "Dependencies conflict" when running `mix deps.get`

**Solution**:

```bash
# Try cleaning and reinstalling
rm -rf deps _build
mix deps.clean --all
mix deps.get
mix deps.compile
```

### Module not found

**Problem**: "module Foo not found" when it clearly exists

**Solution**:

```bash
# Clean and recompile
mix clean
mix compile

# If in IEx, use:
recompile()
```

## Test Issues

### Tests fail with database errors

**Problem**: Tests can't connect to database or tables don't exist

**Solution**:

```bash
# Make sure PostgreSQL is running
docker-compose -f etc/docker/docker-compose.yml up -d postgres

# Set up test database
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate

# Run tests again
make test
```

### Tests timeout

**Problem**: Tests hang or timeout

**Solution**:

```bash
# Run with trace to see which test is hanging
mix test --trace

# Check for infinite loops or blocked processes
# Look at the last test that ran before hanging
```

### Flaky tests

**Problem**: Tests pass sometimes, fail others

**Solution**:

1. Check for async issues (tests that should run synchronously)
2. Look for hardcoded sleeps or timeouts
3. Check for test isolation issues (tests affecting each other)
4. Run the failing test in isolation:

```bash
# Run a specific test file
mix test test/path/to/test_file.exs

# Run a specific test
mix test test/path/to/test_file.exs:42
```

## Clean Slate Solutions

### Nuclear option: Start completely fresh

**Problem**: Everything is broken and you don't know why

**Solution**:

```bash
# 1. Stop all running processes
# Press Ctrl+C in all terminal windows

# 2. Clean everything
make clean

# 3. Remove compiled Elixir files
rm -rf _build deps

# 4. Remove Docker volumes
docker-compose -f etc/docker/docker-compose.yml down -v

# 5. Reinstall everything
asdf install
mix deps.get
make dev-setup

# 6. Start fresh
make dev
```

## Getting Help

### Before asking for help

1. **Check the logs**: Most issues show clear error messages
2. **Read the error message carefully**: It usually tells you what's wrong
3. **Try the troubleshooting steps above**: Most issues are common
4. **Search for the error**: Google/Stack Overflow often have answers
5. **Check recent changes**: Did you change something that might have broken it?

### How to ask for help

When asking for help, provide:

1. **What you're trying to do**: "I'm trying to run make dev"
2. **What happened**: "The server crashes on startup"
3. **Error messages**: Copy the full error message
4. **What you've tried**: "I've tried restarting Docker"
5. **Your environment**:
   ```bash
   elixir --version
   docker --version
   cat .tool-versions
   ```

### Where to ask for help

- **Project team**: Your team members who know the codebase
- **Phoenix Forum**: https://elixirforum.com/c/phoenix-forum
- **Phoenix Discord**: https://discord.gg/elixir
- **Stripe Support**: https://support.stripe.com/ (for Stripe-specific issues)

## Additional Resources

- **Phoenix Docs**: https://hexdocs.pm/phoenix
- **Elixir Docs**: https://hexdocs.pm/elixir
- **Docker Docs**: https://docs.docker.com
- **Stripe Docs**: https://stripe.com/docs
- **PostgreSQL Docs**: https://www.postgresql.org/docs/

## Still Having Issues?

If you're still stuck after trying these solutions:

1. Check if there's an open issue in the project's issue tracker
2. Ask your team members - they may have encountered the same issue
3. Create a detailed issue with all the information from "How to ask for help" above
