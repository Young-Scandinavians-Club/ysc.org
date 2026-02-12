# YSC.org

This is the central repository for the YSC web application, a comprehensive platform for managing club activities, memberships, events, and finances. Built with Elixir and the Phoenix framework, it provides a robust and scalable solution for the club's needs.

---

**👋 New to the project?** Start with the [New Developer Guide](docs/NEW_DEVELOPER_GUIDE.md) for a complete overview of all documentation.

---

## Quick Start (For Returning Developers)

Already have everything set up? Here's the quick version:

```bash
# Terminal 1: Start Stripe webhook forwarding
stripe listen --forward-to localhost:4000/webhooks/stripe

# Terminal 2: Start the dev server
make dev

# Visit http://localhost:4000
```

**First time?** Continue reading the full setup guide below.

---

**📚 Also see: [Quick Reference Guide](QUICKREF.md)** - A cheat sheet for common commands and workflows.

---

## Getting Started

This guide will help you set up your local development environment from scratch. Follow these steps in order.

### Setup Overview

Here's what we'll do:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Install Prerequisites                                     │
│    • Docker & Docker Compose                                 │
│    • Elixir & Erlang (via asdf)                             │
│    • Stripe CLI                                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Get Stripe Credentials                                    │
│    • Login to Stripe Dashboard                               │
│    • Copy API keys                                           │
│    • Start webhook forwarding                                │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Configure Environment                                     │
│    • Copy .env.example → .env                                │
│    • Add your Stripe keys                                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Run Setup                                                 │
│    • make dev-setup (installs deps, starts containers)       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Start Development                                         │
│    • Terminal 1: stripe listen --forward-to localhost:4000   │
│    • Terminal 2: make dev                                    │
│    • Visit http://localhost:4000                             │
└─────────────────────────────────────────────────────────────┘
```

### Prerequisites Installation

#### 1. Install Docker and Docker Compose

**macOS:**

```bash
# Install Docker Desktop for Mac (includes Docker Compose)
# Download from: https://www.docker.com/products/docker-desktop
# Or install via Homebrew:
brew install --cask docker

# Start Docker Desktop from Applications folder
# Verify installation:
docker --version
docker-compose --version
```

**Linux (Ubuntu/Debian):**

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group (to run without sudo)
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo apt-get update
sudo apt-get install docker-compose-plugin

# Verify installation:
docker --version
docker compose version
```

#### 2. Install Elixir and Erlang

We use **asdf** to manage Elixir and Erlang versions. This ensures everyone uses the same versions specified in `.tool-versions`.

**macOS:**

```bash
# Install asdf
brew install asdf

# Add asdf to your shell (for zsh, which is default on macOS)
echo -e "\n. $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.zshrc
source ~/.zshrc

# Add Elixir and Erlang plugins
asdf plugin add erlang
asdf plugin add elixir

# Navigate to project directory
cd /path/to/ysc-redesign-ex

# Install versions specified in .tool-versions
asdf install

# Verify installation:
elixir --version
erl -version
```

**Linux:**

```bash
# Install asdf
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0

# Add asdf to your shell (for bash)
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
source ~/.bashrc

# For zsh, use:
# echo '. "$HOME/.asdf/asdf.sh"' >> ~/.zshrc
# source ~/.zshrc

# Install dependencies for Erlang compilation
sudo apt-get install build-essential autoconf m4 libncurses5-dev \
  libwxgtk3.0-gtk3-dev libwxgtk-webview3.0-gtk3-dev libgl1-mesa-dev \
  libglu1-mesa-dev libpng-dev libssh-dev unixodbc-dev xsltproc fop \
  libxml2-utils libncurses-dev openjdk-11-jdk

# Add Elixir and Erlang plugins
asdf plugin add erlang
asdf plugin add elixir

# Navigate to project directory
cd /path/to/ysc-redesign-ex

# Install versions specified in .tool-versions
asdf install

# Verify installation:
elixir --version
erl -version
```

#### 3. Install and Configure Stripe CLI

The Stripe CLI is needed to forward webhook events from Stripe to your local development server.

**Installation:**

```bash
# macOS
brew install stripe/stripe-cli/stripe

# Linux
# Download the latest release from: https://github.com/stripe/stripe-cli/releases
wget https://github.com/stripe/stripe-cli/releases/download/v1.19.5/stripe_1.19.5_linux_x86_64.tar.gz
tar -xvf stripe_1.19.5_linux_x86_64.tar.gz
sudo mv stripe /usr/local/bin/

# Verify installation:
stripe --version
```

**Login to Stripe:**

```bash
# This will open a browser for authentication
stripe login
```

**Get Your Stripe API Keys:**

1. Go to [Stripe Dashboard](https://dashboard.stripe.com/test/apikeys)
2. Make sure you're in **Test Mode** (toggle in the top right)
3. Copy your **Publishable key** (starts with `pk_test_`)
4. Click "Reveal test key token" and copy your **Secret key** (starts with `sk_test_`)

**Start Stripe Webhook Forwarding and Get Webhook Secret:**

```bash
# Start the Stripe CLI webhook forwarding (in a separate terminal)
stripe listen --forward-to localhost:4000/webhooks/stripe

# This will output a webhook signing secret that looks like:
# > Ready! Your webhook signing secret is whsec_xxxxxxxxxxxxxxxxxxxx
# Copy this secret - you'll need it for your .env file
```

Keep this terminal window open while developing. The Stripe CLI will forward webhook events to your local server.

### Environment Configuration

#### Create Your `.env` File

Copy the example environment file and fill in your Stripe credentials:

```bash
# Copy the example file
cp .env.example .env

# Edit the file with your favorite editor
nano .env
# or
vim .env
# or
code .env
```

**You MUST update these three values in your `.env` file:**

1. `STRIPE_SECRET` - Your Stripe secret key from [Stripe Dashboard](https://dashboard.stripe.com/test/apikeys) (starts with `sk_test_`)
2. `STRIPE_PUBLIC_KEY` - Your Stripe publishable key from the same page (starts with `pk_test_`)
3. `STRIPE_WEBHOOK_SECRET` - The webhook secret from running `stripe listen` (starts with `whsec_`)

**Example `.env` file:**

```bash
STRIPE_SECRET=sk_test_51ABC123def456...
STRIPE_PUBLIC_KEY=pk_test_51ABC123def456...
STRIPE_WEBHOOK_SECRET=whsec_abc123def456...
```

All other environment variables are optional and have sensible defaults for local development.

**Security Note:** Never commit your `.env` file to version control. It's already in `.gitignore`.

### Initial Setup

Now that all prerequisites are installed and configured, set up the development environment:

```bash
# Install dependencies and set up database
# This will:
# - Install Elixir dependencies
# - Start Docker containers (PostgreSQL, LocalStack S3, etc.)
# - Wait for database to be ready
# - Run database migrations
# - Seed the database with initial data
make dev-setup
```

This command will take a few minutes the first time as it downloads Docker images and compiles dependencies.

### Seeded Development Data

The `make dev-setup` command automatically seeds your database with test data for development. This includes:

#### Default Admin User

You can log in immediately with the default admin account:

**Email**: `admin@ysc.org`
**Password**: `very_secure_password`

This account has full administrative access to the application.

#### Other Seeded Data

The seeds also create:

- **10 active members** with various membership types (single and family)
- **5 pending members** awaiting approval
- **3 rejected applications**
- **User notes** on various accounts (for testing the notes feature)
- **Sample posts** with images
- **Sample events** (both past and upcoming, free and paid)
- **Event ticket tiers** and agendas
- **Tahoe cabin rooms** with images
- **Social media links** (Instagram, Facebook, Discord)

All seeded users (except admin) follow the pattern:

- **Email**: `firstname_lastname_N@ysc.org` (e.g., `karl_andersson_0@ysc.org`)
- **Password**: `very_secure_password` (same as admin)

### Start the Development Server

```bash
# Start the Phoenix development server
make dev
```

The `make dev` command now includes automatic checks to ensure everything is ready:

- ✅ **Environment variables** - Verifies Stripe credentials are set
- ✅ **Docker containers** - Checks PostgreSQL and LocalStack are running
- ✅ **Database connection** - Ensures database is accessible
- ✅ **Migrations** - Verifies all migrations have been applied

If any check fails, you'll get a helpful error message with instructions on how to fix it.

**Example output:**

```
🔍 Checking prerequisites...

→ Checking environment variables...
✓ Environment variables configured

→ Checking Docker containers...
✓ PostgreSQL container is running
✓ LocalStack container is running

→ Checking database connection...
✓ Database connection successful

→ Checking database migrations...
✓ All migrations applied

✓ All checks passed!

🚀 Starting Phoenix server...
Visit http://localhost:4000
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

**You should have three terminal windows open:**

1. **Stripe CLI** - Running `stripe listen --forward-to localhost:4000/webhooks/stripe`
2. **Phoenix Server** - Running `make dev`
3. **Your working terminal** - For running commands, tests, etc.

### Verify Your Setup

1. Open your browser to [http://localhost:4000](http://localhost:4000)
2. You should see the YSC homepage
3. Test that webhooks are working by creating a test payment (Stripe CLI should show events being forwarded)

### Troubleshooting

**Having issues?** See the comprehensive [Troubleshooting Guide](docs/TROUBLESHOOTING.md) for detailed solutions.

**Quick fixes for common issues:**

**Docker containers won't start:**

```bash
# Check if Docker Desktop is running (macOS)
# Check Docker daemon status (Linux)
sudo systemctl status docker

# Restart Docker containers
docker-compose -f etc/docker/docker-compose.yml down
docker-compose -f etc/docker/docker-compose.yml up -d

# Check container logs
docker-compose -f etc/docker/docker-compose.yml logs
```

**Database connection errors:**

```bash
# Ensure PostgreSQL container is running
docker-compose -f etc/docker/docker-compose.yml ps

# Reset the database
make reset-db
make setup-dev-db
```

**Missing Stripe environment variables:**

```bash
# Verify your .env file exists and has the correct values
cat .env

# Make sure the webhook secret matches the one from `stripe listen`
# Restart the Phoenix server after updating .env
```

**Stripe webhooks not working:**

```bash
# Make sure Stripe CLI is running in a separate terminal
stripe listen --forward-to localhost:4000/webhooks/stripe

# Check the webhook secret in your .env matches the one from stripe listen
```

**Port already in use (4000):**

```bash
# Find what's using port 4000
lsof -i :4000

# Kill the process or use a different port by setting PORT=4001 in your .env
```

**Clean slate reset:**

```bash
# If everything is broken, start fresh
make clean           # Removes Docker containers and build artifacts
make dev-setup       # Set up everything again
```

### Useful Development Tools

The following services are available while running the dev environment:

- **Application**: [http://localhost:4000](http://localhost:4000)
- **Email Preview (Swoosh)**: [http://localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox)
  - View all emails sent by the YSC application
  - User registration, password resets, notifications, etc.
  - Emails are stored in memory (not actually sent)
- **PgAdmin** (Database UI): [http://localhost:8888](http://localhost:8888)
  - Email: `admin@ysc.org`
  - Password: `password`
- **LocalStack** (Local AWS S3): [http://localhost:4566](http://localhost:4566)

### Testing Emails in Development

The application uses **Swoosh** for sending emails. In development mode, emails are **not actually sent** to real email addresses. Instead, they're stored in memory and can be viewed in your browser.

#### Viewing Application Emails (Swoosh Mailbox)

All emails sent by the YSC application can be viewed at:

**[http://localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox)**

This includes:

- 🔐 **User registration confirmations**
- 🔑 **Password reset emails**
- ✉️ **Account notifications**
- 📧 **Membership-related emails**
- 📋 **Event confirmations**
- 💳 **Payment receipts**
- 🎫 **Ticket confirmations**
- And all other transactional emails

#### How It Works

```
YSC App sends email → Swoosh.Adapters.Local → Stored in memory
                                                     ↓
                                    Viewable at /dev/mailbox
```

**Key points:**

- Emails persist only while the Phoenix server is running
- Restarting the server clears all stored emails
- No external SMTP server needed
- Perfect for testing email templates and content

#### Testing Email Flows

**1. Test user registration email:**

```bash
# Start the dev server
make dev

# Register a new user at http://localhost:4000/users/register
# Enter email: test@example.com

# View the confirmation email
open http://localhost:4000/dev/mailbox
```

**2. Test password reset email:**

```bash
# Go to http://localhost:4000/users/reset-password
# Enter any email address

# View the reset email
open http://localhost:4000/dev/mailbox
```

**3. Test event/ticket emails:**

```bash
# Purchase a ticket or register for an event
# Check /dev/mailbox for confirmation email
```

#### Email Preview Features

The Swoosh mailbox preview provides:

- **List view** - See all sent emails chronologically
- **Email details** - View full email content (HTML and text versions)
- **Metadata** - See recipient, subject, from address
- **Live updates** - New emails appear automatically
- **Search/filter** - Find specific emails easily

#### Testing Email Templates

If you're developing email templates:

```bash
# 1. Make changes to email template
# Example: lib/ysc_web/emails/templates/user_confirmation.mjml.eex

# 2. Trigger the email
# Register a new user or use the action

# 3. View in mailbox
open http://localhost:4000/dev/mailbox

# 4. Check both HTML and text versions
# Click on the email to see full preview
```

#### Troubleshooting Email Testing

**Emails not appearing in /dev/mailbox:**

```bash
# Check that dev_routes are enabled
# This should be true in development (default)

# Verify Swoosh configuration
# In config/config.exs, should see:
# config :ysc, Ysc.Mailer, adapter: Swoosh.Adapters.Local

# Restart the Phoenix server
# Press Ctrl+C twice, then: make dev
```

**Mailbox is empty after restart:**

- This is expected - emails are stored in memory only
- They're cleared when the server restarts
- Generate new test emails as needed

**Need to test actual email delivery:**

- Use a test SMTP service (e.g. MailHog or Mailtrap)
- Configure in `config/dev.exs` or use environment variables
- For most development, the Swoosh local adapter and dev mailbox are sufficient

### Newsletter subscriptions

The application uses an in-house newsletter system (`Ysc.Newsletter`) for managing subscriptions. Subscriptions are stored in the `newsletter_subscribers` table.

**Where users can subscribe or manage preferences:**

- **Homepage** (unauthenticated): Newsletter signup form at the bottom of the page
- **User settings** (authenticated): Notifications → Newsletter checkbox
- **Public unsubscribe**: Each subscriber has a unique link to unsubscribe: `/newsletter/unsubscribe/:token`

**Testing in IEx:**

```elixir
# Subscribe an email
Ysc.Newsletter.subscribe("test@example.com", source: "public_signup")

# Find subscriber
Ysc.Newsletter.get_subscriber_by_email("test@example.com")

# Unsubscribe
Ysc.Newsletter.unsubscribe("test@example.com")
# Or by token:
Ysc.Newsletter.unsubscribe(subscriber.subscription_token)
```

Newsletter sending/campaigns are not part of this system; it only manages subscription state.

### Next Steps

Now that you have a working development environment:

1. **📚 Bookmark the [Quick Reference Guide](QUICKREF.md)** - Keep it handy for common commands
2. **📐 Understand the system** - Read the [Development Architecture Guide](docs/DEVELOPMENT_ARCHITECTURE.md)
3. **Read the Contributing section** to understand the development workflow
4. **Run `make help`** to see all available commands
5. **Explore the codebase** - start with `lib/ysc_web/` for web interface code
6. **Run tests** with `make test` to ensure everything works
7. **Before committing**, always run `make preflight` to catch issues early

## Deployment & Environments

The application is configured to run in three main environments: development, sandbox, and production.

### Development

The development environment is configured for local development. You can set it up and run it using the `make dev-setup` and `make dev` commands. It runs with hot-reloading enabled.

### Sandbox (Fly.io)

The project includes a sandbox environment deployed on Fly.io for testing integrations in a production-like environment.

#### Sandbox Configuration

- **URL**: https://ysc-sandbox.fly.dev
- **Environment**: Sandbox (auto-shuts down after 10 minutes of inactivity)
- **QuickBooks**: Uses QuickBooks Sandbox API
- **Stripe**: Uses Stripe test mode

#### Deploying to Sandbox

To deploy changes to the sandbox environment:

```bash
make deploy-sandbox
```

### Production

The production environment is hosted on Fly.io. For detailed deployment instructions, please refer to the official Phoenix deployment guides.

## Architecture

This is a web application built with the Phoenix framework, written in Elixir. It follows the standard Phoenix project structure:

- **Core Business Logic (`lib/ysc`)**: This layer encapsulates the core functionalities of the application, such as user accounts, payments, bookings, and integrations with third-party services like Stripe and QuickBooks. It is decoupled from the web interface.
- **Web Interface (`lib/ysc_web`)**: This is the Phoenix web application that provides the user interface. It uses Phoenix LiveView for rich, real-time user experiences, and traditional controllers for handling HTTP requests. It's responsible for rendering templates, handling user input, and communicating with the core business logic.
- **Database**: The application uses a PostgreSQL database, managed by Ecto, Elixir's database wrapper and query language.
- **Background Jobs**: Asynchronous tasks, like sending emails or syncing with QuickBooks, are managed by Oban, a robust background job processing library for Elixir.
- **Third-Party Integrations**:
  - **Stripe**: For payment processing.
  - **QuickBooks**: For accounting and financial management.
  - **AWS S3**: For file storage.
  - **Flowroute**: For SMS services.

## Features

The application provides a comprehensive set of features for managing a club or organization:

- **User Management**: User accounts, authentication, and authorization.
- **Membership Management**: Handling memberships, subscriptions, and renewals.
- **Event Management**: Creating and managing events, including ticketing and registration.
- **Bookings**: A system for booking resources or facilities.
- **Content Management**: Creating and publishing posts and announcements.
- **Financial Management**:
  - Processing payments with Stripe.
  - Generating expense reports.
  - Syncing financial data with QuickBooks.
  - Maintaining ledgers and financial records.
- **Communication**: Sending emails and SMS messages to users.
- **Support**: A ticketing system for handling user inquiries.
- **File Management**: Uploading and managing files with AWS S3.
- **Search**: A comprehensive search functionality.

## Contributing

Contributions to this project are managed by the web tech group. Here's the general workflow for making changes:

1.  **Create a branch**: Create a new branch from `main` for your feature or bug fix. Use a descriptive name (e.g., `feature/add-dark-mode` or `fix/login-bug`).
2.  **Make your changes**: Implement your changes, following the project's coding style and conventions.
3.  **Write tests**: Add tests to cover any new functionality or bug fixes.
4.  **Run preflight checks**: Before committing, run `make preflight` to ensure all CI checks pass locally.
5.  **Submit a pull request**: Open a pull request from your branch to the `main` branch. Provide a clear description of your changes and why they are needed.

A team member will review your pull request. Thank you for your contribution!

### Before You Commit

**Always run `make preflight` before pushing your code!** This command runs all the same checks that will run in CI (GitHub Actions), catching issues early:

```bash
make preflight
```

This single command will:

- Compile your code with warnings as errors
- Check code formatting
- Run Credo (strict mode)
- Run Sobelow security audit
- Audit dependencies for vulnerabilities
- Run the complete test suite with coverage

If all checks pass, your code is ready to push. If any check fails, you'll get clear feedback on what needs to be fixed.

### Testing QuickBooks Integration

To test QuickBooks integration locally, you'll need to configure QuickBooks sandbox credentials:

1. **Get QuickBooks Sandbox Credentials**:
   - Sign up for a [QuickBooks Developer Account](https://developer.intuit.com/)
   - Create a sandbox company in the QuickBooks Developer Dashboard
   - Create an app and obtain OAuth credentials

2. **Set QuickBooks Environment Variables**:

   Add these to your `.env` file or export them:

   ```bash
   # QuickBooks Sandbox Configuration
   QUICKBOOKS_CLIENT_ID=your_client_id
   QUICKBOOKS_CLIENT_SECRET=your_client_secret
   QUICKBOOKS_COMPANY_ID=your_company_id
   QUICKBOOKS_ACCESS_TOKEN=your_access_token
   QUICKBOOKS_REFRESH_TOKEN=your_refresh_token
   QUICKBOOKS_REALM_ID=your_realm_id
   QUICKBOOKS_APP_ID=your_app_id
   QUICKBOOKS_BASE_URL=https://sandbox-quickbooks.api.intuit.com/v3

   # QuickBooks Account IDs (required - get these from your sandbox company)
   QUICKBOOKS_BANK_ACCOUNT_ID=35
   QUICKBOOKS_STRIPE_ACCOUNT_ID=1150040000

   # QuickBooks Item IDs (optional - will auto-create if not set)
   QUICKBOOKS_EVENT_ITEM_ID=optional_item_id
   QUICKBOOKS_DONATION_ITEM_ID=optional_item_id
   QUICKBOOKS_TAHOE_BOOKING_ITEM_ID=optional_item_id
   QUICKBOOKS_CLEAR_LAKE_BOOKING_ITEM_ID=optional_item_id
   QUICKBOOKS_MEMBERSHIP_ITEM_ID=optional_item_id
   ```

3. **Test QuickBooks Sync**:
   - Create a payment, refund, or payout in the application
   - The system will automatically enqueue a QuickBooks sync job via Oban
   - Check the Oban dashboard at `/admin/settings` to monitor sync jobs
   - Verify the sync in your QuickBooks sandbox company

**Note:** QuickBooks sync jobs run asynchronously via Oban. You can monitor job status in the admin settings page.

### Development Commands

The project includes several useful make targets for development:

#### Pre-Commit Checks

- **`make preflight`** - **Run this before every commit!** Executes all CI checks locally:
  - Compiles code with warnings as errors
  - Checks code formatting
  - Runs Credo in strict mode
  - Runs Sobelow security audit
  - Audits dependencies for vulnerabilities
  - Runs complete test suite with coverage
  - If all checks pass, your code is ready to push to CI

#### Code Quality

- **`make format`** - Format all Elixir code using the project's formatter
- **`make lint`** - Run the full lint suite:
  - Runs Credo for code analysis
  - Checks that all files are properly formatted
  - Use this before committing code

#### Testing

- **`make test`** or **`make tests`** - Run the full test suite
  - Automatically starts PostgreSQL if needed
  - Runs all tests with coverage
- **`make test-failed`** - Run only tests that failed in the previous test run
  - Useful for iterating on failing tests

#### Database Management

- **`make reset-db`** - Drop the local development database
- **`make setup-dev-db`** - Create, migrate, and seed the local development database
  - Useful for resetting your local database to a clean state

#### Development Tools

- **`make shell`** - Open an IEx (Interactive Elixir) shell with the application loaded
  - Useful for debugging and exploring the codebase interactively
- **`make clean`** - Clean up Docker containers, volumes, and Elixir build artifacts
  - Use when you need a fresh start

#### Deployment

- **`make deploy-sandbox`** - Deploy the application to the Fly.io sandbox environment
  - Requires Fly.io CLI and authentication

#### Getting Help

- **`make help`** - Display all available make targets with descriptions

## Environment Variables

**Important:** All Stripe environment variables must be set before running `make dev`. You can either export them in your shell or use a `.env` file.

### Required Stripe Configuration

- `STRIPE_SECRET` - Your Stripe secret key
- `STRIPE_PUBLIC_KEY` - Your Stripe publishable key
- `STRIPE_WEBHOOK_SECRET` - Your Stripe webhook secret

You can get these from your [Stripe Dashboard](https://dashboard.stripe.com/apikeys).

### QuickBooks Configuration (Optional, for testing QuickBooks integration)

- `QUICKBOOKS_CLIENT_ID` - QuickBooks OAuth client ID
- `QUICKBOOKS_CLIENT_SECRET` - QuickBooks OAuth client secret
- `QUICKBOOKS_COMPANY_ID` - QuickBooks company ID
- `QUICKBOOKS_ACCESS_TOKEN` - OAuth access token
- `QUICKBOOKS_REFRESH_TOKEN` - OAuth refresh token
- `QUICKBOOKS_REALM_ID` - QuickBooks realm ID
- `QUICKBOOKS_APP_ID` - QuickBooks app ID
- `QUICKBOOKS_BASE_URL` - QuickBooks API base URL (defaults to sandbox: `https://sandbox-quickbooks.api.intuit.com/v3`)
- `QUICKBOOKS_BANK_ACCOUNT_ID` - QuickBooks bank account ID (required)
- `QUICKBOOKS_STRIPE_ACCOUNT_ID` - QuickBooks Stripe account ID (required)
- `QUICKBOOKS_EVENT_ITEM_ID` - QuickBooks event item ID (optional, auto-created if not set)
- `QUICKBOOKS_DONATION_ITEM_ID` - QuickBooks donation item ID (optional)
- `QUICKBOOKS_TAHOE_BOOKING_ITEM_ID` - QuickBooks Tahoe booking item ID (optional)
- `QUICKBOOKS_CLEAR_LAKE_BOOKING_ITEM_ID` - QuickBooks Clear Lake booking item ID (optional)
- `QUICKBOOKS_MEMBERSHIP_ITEM_ID` - QuickBooks membership item ID (optional)

**Note:** For local development, use QuickBooks Sandbox credentials. The sandbox environment on Fly.io is pre-configured with these values.

### Optional Configuration

- `RADAR_PUBLIC_KEY` - Your Radar public key for map functionality (defaults to test key if not set)

- `EMAIL_FROM` - Email address used as sender for outgoing emails (defaults to "info@ysc.org")
- `EMAIL_FROM_NAME` - Display name for outgoing emails (defaults to "YSC")
- `EMAIL_CONTACT` - General contact email address (defaults to "info@ysc.org")
- `EMAIL_ADMIN` - Admin email address (defaults to "admin@ysc.org")
- `EMAIL_MEMBERSHIP` - Membership-related email address (defaults to "membership@ysc.org")
- `EMAIL_BOARD` - Board email address (defaults to "board@ysc.org")
- `EMAIL_VOLUNTEER` - Volunteer email address (defaults to "volunteer@ysc.org")
- `EMAIL_TAHOE` - Tahoe cabin email address (defaults to "tahoe@ysc.org")
- `EMAIL_CLEAR_LAKE` - Clear Lake cabin email address (defaults to "cl@ysc.org")

### Setting Environment Variables

You can set these variables in one of two ways:

#### Option 1: Export in your shell

```bash
export STRIPE_SECRET="sk_test_..."
export STRIPE_PUBLIC_KEY="pk_test_..."
export STRIPE_WEBHOOK_SECRET="whsec_..."
export RADAR_PUBLIC_KEY="prj_live_pk_..."  # Optional, defaults to test key
```

#### Option 2: Create a `.env` file

Create a `.env` file in the project root:

```bash
# Stripe (Required)
STRIPE_SECRET=sk_test_...
STRIPE_PUBLIC_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# QuickBooks (Optional, for testing QuickBooks integration)
QUICKBOOKS_CLIENT_ID=your_client_id
QUICKBOOKS_CLIENT_SECRET=your_client_secret
QUICKBOOKS_COMPANY_ID=your_company_id
QUICKBOOKS_ACCESS_TOKEN=your_access_token
QUICKBOOKS_REFRESH_TOKEN=your_refresh_token
QUICKBOOKS_REALM_ID=your_realm_id
QUICKBOOKS_APP_ID=your_app_id
QUICKBOOKS_BASE_URL=https://sandbox-quickbooks.api.intuit.com/v3
QUICKBOOKS_BANK_ACCOUNT_ID=35
QUICKBOOKS_STRIPE_ACCOUNT_ID=1150040000

# Optional
RADAR_PUBLIC_KEY=prj_live_pk_...  # Optional, defaults to test key
```

**Note:** Exported environment variables take precedence over values in the `.env` file. The `make dev` command will automatically load variables from `.env` if the file exists.

**Security Note:** Never commit your `.env` file to version control. It's already included in `.gitignore`.
