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

#### 4. Install Shell Script Tools (ShellCheck and shfmt)

ShellCheck and shfmt are used to lint and format shell scripts. They are required for `mix precommit` and `make preflight`.

**macOS:**

```bash
brew install shellcheck shfmt

# Verify installation:
shellcheck --version
shfmt --version
```

**Linux (Ubuntu/Debian):**

```bash
sudo apt-get update
sudo apt-get install -y shellcheck shfmt

# Verify installation:
shellcheck --version
shfmt --version
```

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

### User Management & Authentication

Comprehensive user account management with multiple authentication methods and robust security features:

#### Multiple Authentication Methods

- **Email + Password**: Traditional authentication with secure password hashing (Bcrypt)
- **Passkeys (WebAuthn)**: Passwordless authentication using biometric devices (Face ID, Touch ID, Windows Hello, security keys)
  - FIDO2/WebAuthn standard implementation
  - Support for multiple passkeys per user
  - Device-based nicknames for easy management
  - Sign-count tracking to detect cloned credentials
  - User verification required for all operations
- **OAuth 2.0 Social Login**:
  - **Google OAuth**: Sign in with Google accounts
  - **Facebook OAuth**: Sign in with Facebook accounts
  - Automatic email verification for OAuth users
  - Seamless account linking if email already exists
- **Hybrid Authentication**: Users can combine multiple methods (e.g., password + passkey for backup)

#### Passkey Features

- **Registration Flow**: Simple enrollment process with device nickname selection
- **Authentication Flow**: Fast, secure login without passwords
- **Multiple Devices**: Support unlimited passkeys per user (laptop, phone, security keys)
- **Cross-Platform**: Works on iOS, Android, macOS, Windows with WebAuthn-compatible devices
- **Security**: Private keys never leave the device; public key stored on server
- **Prompt Dismissal**: Optional one-time dismissal of passkey enrollment prompts
- **Usage Tracking**: Last used timestamp and sign-count for each passkey
- **Email Notifications**: Alerts when new passkeys are added

#### Re-authentication System

- **Sensitive Operations Protection**: Password changes and email changes require recent authentication
- **Multiple Re-auth Methods**: Re-authenticate with password or passkey
- **Session Validation**: Ensure user is still in control of the account before critical changes
- **Modal Flow**: Seamless in-page re-authentication without full page redirects

#### Security Features

- **Rate Limiting**: Protection against credential stuffing and brute force attacks
  - IP-based limits: 20 authentication attempts per minute
  - Email-based limits: 5 attempts per minute per account
  - Automatic lockout with retry-after delays
- **Authentication Event Logging**: Comprehensive audit trail of all auth events
  - Login successes/failures with timestamps
  - Device information (browser, OS, device type)
  - IP address and geolocation tracking
  - User agent parsing
  - Session tracking
- **Suspicious Activity Detection**: Automated threat monitoring
  - Rapid failed login attempts
  - Unusual login times (after hours)
  - New device detection
  - Risk scoring based on threat indicators
- **Security Notifications**: Automatic alerts for critical events
  - Email notifications for password changes
  - SMS alerts for password and email changes
  - Passkey addition confirmations
- **Password Security**:
  - Bcrypt hashing with configurable work factor
  - Password strength validation
  - Secure password reset flow with time-limited tokens
  - Change password with current password verification

#### Account State Management

- **User States**: Pending approval, active, rejected, suspended
- **Email Verification**: Required for email/password signups
- **OAuth Auto-verification**: OAuth users marked as verified automatically
- **Account Locking**: Automatic lockout after repeated failed attempts

#### Authentication Session Features

- **Remember Me**: Optional extended sessions (60 days vs default)
- **Session History**: View all login sessions with device and location info
- **Last Login Display**: Show users their last successful login
- **Active Session Tracking**: Monitor current and past sessions
- **Secure Logout**: Full session termination with event logging

#### Security Dashboard

- **User Security Settings Page**: Centralized security management
  - Change password
  - Add/remove passkeys
  - View active sessions
  - Review authentication history
  - Manage security preferences
- **Security Alerts**: Real-time display of suspicious activity

**Related Documentation:**

- [User Authentication Guide](docs/USER_AUTHENTICATION.md)
- [Passkey Implementation](docs/PASSKEY_SETUP.md)
- [OAuth Setup Guide](docs/OAUTH_SETUP.md)
- [Security & Rate Limiting](docs/SECURITY.md)
- [Re-authentication Flow](docs/REAUTH_IMPLEMENTATION_SUMMARY.md)

### Membership Management

A complete membership lifecycle management system with:

- **Automatic Renewals**: Seamless recurring billing through Stripe with configurable renewal periods
- **Membership Tiers**: Support for single and family membership types
- **Flexible Transitions**: Members can upgrade or downgrade between single and family memberships at any time
- **Lifetime Memberships**: Special non-expiring membership tier for lifetime supporters
- **Family Accounts**: Sub-accounts system where family members automatically inherit membership status from a parent account
- **Member Portal**: Self-service dashboard for members to manage their subscriptions and account details

**Related Documentation:**

- [Membership System Overview](docs/MEMBERSHIP_SYSTEM.md)
- [Stripe Integration Guide](docs/STRIPE_INTEGRATION.md)

### Membership Application & Admin Review System

A comprehensive membership application workflow with multi-step verification and admin review:

#### Application Process

##### Multi-Step Application Form

- **Step-by-Step Flow**: Guided application process with progress tracking
- **Account Creation**: Email and password setup with verification
- **Personal Information**: Name, date of birth, contact details
- **Address Collection**: Full mailing address with country, city, region, postal code
- **Nordic Connection**: Place of birth, citizenship, most connected Nordic country

##### Eligibility Verification

- **Multiple Eligibility Criteria**: Applicants select all that apply
  - Citizen of a Scandinavian country (Denmark, Finland, Iceland, Norway, Sweden)
  - Born in Scandinavia
  - Scandinavian parent, grandparent, or great-grandparent
  - Lived in Scandinavia for at least 6 months
  - Speak a Scandinavian language
  - Spouse of a member
- **Free-Form Responses**: Open-text fields for detailed explanations
  - Link to Scandinavia (personal connection description)
  - Time lived in Scandinavia (if applicable)
  - Spoken languages
  - How they heard about the club

##### Membership Type Selection

- **Single Membership**: Individual membership
- **Family Membership**: Include spouse and/or children
  - Family member details (name, birth date, relationship type)
  - Multiple family members supported

##### Legal Requirements

- **Bylaws Agreement**: Must review and accept club bylaws
- **Timestamp Tracking**: Agreement timestamp recorded
- **Occupation Field**: Required for application

##### Application Tracking

- **Draft State**: Applications can be started and saved
- **Submission Timestamp**: Completion time recorded with timezone
- **Browser Timezone**: Captured for accurate time display

#### Admin Review Interface

##### Application Dashboard

- **Pending Applications**: List view of all applications awaiting review
  - Sortable and filterable by name, email, submission date, state
  - Pagination with configurable limits (50-200 per page)
  - Visual status badges (pending, approved, rejected)
- **Search & Filters**: Find applications by email, name, phone, state, or role
- **Submission Age**: "Time ago" display (e.g., "3 days ago")

##### Detailed Application View

- **Complete Application Display**: Modal view with all submitted information
  - Applicant details (email, name, birth date)
  - Family members (if family membership)
  - Membership type and eligibility reasons
  - Personal background (occupation, place of birth, citizenship)
  - Nordic connection details
  - Free-form responses
- **Previous Review Info**: If already reviewed, shows outcome, date, and reviewer
- **Visual Organization**: Categorized sections with clear headings

##### Review Actions

- **Approve Application**:
  - Changes user state from `pending_approval` to `active`
  - Sends approval email to applicant
  - Records reviewer user ID and timestamp
  - Sets review outcome to `approved`
  - Logs review event in audit trail
- **Reject Application**:
  - Changes user state to `rejected`
  - Sends rejection email with optional feedback
  - Records reviewer and timestamp
  - Sets review outcome to `rejected`
  - Logs review event
- **Re-review**: Previously reviewed applications can be reviewed again if needed

#### User State Management

##### Account States

- **Pending Approval**: Initial state after application submission
  - Limited access (can view pending page)
  - Cannot access member-only features
  - Waiting for admin review
- **Active**: Approved members with full access
  - Can purchase memberships
  - Access to all member features
  - Can book cabins and register for events
- **Rejected**: Applications denied
  - Can reapply after rejection
  - Receives rejection notification
- **Suspended**: Temporarily restricted access
- **Deleted**: Soft-deleted accounts

#### Admin Notes System

- **Internal Notes**: Admins can add notes to any user account
- **Note Categories**: Categorized notes for organization
  - General notes
  - Membership issues
  - Conduct concerns
  - Payment issues
- **Immutable Records**: Notes cannot be edited once created
- **Audit Trail**: Creator and timestamp tracked for each note
- **Private**: Notes only visible to admins, never to users

#### Notification System

##### Applicant Notifications

- **Application Submitted**: Confirmation email upon submission
- **Application Approved**: Welcome email with next steps
- **Application Rejected**: Notification with reasons (if provided)
- **Admin Alert**: Board members notified of new applications

##### Admin Notifications

- **New Application Alert**: Email to admins when application submitted
  - Includes applicant summary
  - Direct link to review page
  - Sent to configured admin email addresses

#### Review Event Logging

- **Event Tracking**: All review actions logged in audit trail
- **Event Types**: Submitted, approved, rejected
- **Metadata**: Reviewer ID, timestamp, outcome
- **Historical Record**: Complete application lifecycle history

#### Security & Access Control

- **Admin-Only Access**: Review interface restricted to admin role
- **Ownership Validation**: Users can only view their own applications
- **Role-Based Permissions**: Separate permissions for viewing vs. reviewing
- **Impersonation Support**: Admins can impersonate users for troubleshooting (separate feature)

**Related Documentation:**

- [Membership Application Guide](docs/MEMBERSHIP_APPLICATION.md)
- [Admin Review Process](docs/ADMIN_REVIEW.md)
- [User States & Permissions](docs/USER_STATES.md)

### Event Management

Comprehensive event creation and management with:

- **Configurable Ticket Tiers**: Create multiple pricing tiers for events (e.g., General Admission, VIP, Early Bird)
- **Optional Donations**: Allow attendees to add donations when purchasing tickets
- **Partiful Integration**: Optional integration with Partiful for event coordination and RSVPs
- **Event Registration**: Handle both free and paid event registrations
- **Capacity Management**: Set attendance limits and track availability
- **Event Calendar**: Display upcoming and past events with filtering options

**Related Documentation:**

- [Event Management Guide](docs/EVENT_MANAGEMENT.md)
- [Partiful Integration](docs/PARTIFUL_INTEGRATION.md)

### Content Management

Creating and publishing posts and announcements with:

- **News System**: Post news articles and updates with rich media support
- **Member Comments**: Members can comment on news posts to foster community engagement
- **Access Control**: Comments restricted to members only to maintain community quality
- **Media Gallery**: Support for images and attachments in posts

**Related Documentation:**

- [Content Management Guide](docs/CONTENT_MANAGEMENT.md)

### Newsletter System

Manage communications with members and subscribers:

- **Subscription Management**: Users can subscribe/unsubscribe through multiple touchpoints (homepage, user settings, email links)
- **Subscription Sources**: Track where subscribers came from (public signup, user settings, etc.)
- **Unique Unsubscribe Links**: Each subscriber receives a secure, unique token for one-click unsubscription
- **Integration Points**:
  - Homepage footer signup form
  - User settings notifications panel
  - Public unsubscribe page
- **Privacy Controls**: Self-service subscription management without requiring login

**Testing in IEx:**

```elixir
# Subscribe an email
Ysc.Newsletter.subscribe("test@example.com", source: "public_signup")

# Find subscriber
Ysc.Newsletter.get_subscriber_by_email("test@example.com")

# Unsubscribe by email or token
Ysc.Newsletter.unsubscribe("test@example.com")
Ysc.Newsletter.unsubscribe(subscriber.subscription_token)
```

**Related Documentation:**

- [Newsletter System Guide](docs/NEWSLETTER_SYSTEM.md)

### Booking System

A comprehensive property booking system for cabin rentals (Tahoe and Clear Lake) with advanced features:

#### Seasonal Configuration

- **Recurring Seasons**: Define seasons with automatic annual recurrence (e.g., Winter: Nov 1 - Apr 30, Summer: May 1 - Oct 31)
- **Year-Spanning Support**: Seasons can span calendar years naturally (winter seasons from November to April)
- **Default Seasons**: Set fallback seasons for each property
- **Per-Season Rules**: Configure different booking rules and pricing for each season

#### Flexible Booking Modes

- **Room-Based Bookings**: Book specific rooms with per-person-per-night pricing (Tahoe cabins)
- **Day-Pass Bookings**: Day-only access without room assignments with per-guest-per-day pricing (Clear Lake)
- **Property Buyouts**: Book the entire property for exclusive use at a fixed price

#### Advanced Pricing Configuration

- **Hierarchical Pricing Rules**: Three-tier pricing specificity
  - Room-specific pricing (highest priority)
  - Category-based pricing (medium priority)
  - Property + season default pricing (fallback)
- **Children Pricing**: Optional separate pricing tiers for children
- **Dynamic Pricing**: Different rates by season, room category, or individual room
- **Multiple Price Units**: Support for per-person-per-night, per-guest-per-day, and fixed buyout pricing

#### Booking Rules & Restrictions

- **Advance Booking Windows**: Configure how far in advance bookings can be made per season (e.g., 45 days)
- **Maximum Night Limits**: Set maximum stay duration per season or use property defaults (Tahoe: 4 nights, Clear Lake: 30 nights)
- **Blackout Dates**: Block specific date ranges for maintenance, events, or other reasons
- **Minimum Billable Occupancy**: Set minimum guest requirements for rooms (e.g., family rooms requiring 2+ guests)
- **Capacity Management**: Define maximum capacity per room with granular bed configuration (single, queen, king beds)

#### Refund Policy Management

- **Configurable Refund Policies**: Create property and booking-mode-specific refund policies
- **Time-Based Refund Rules**: Define refund percentages based on days before check-in
- **Automatic Refund Calculation**: System calculates applicable refund amounts based on cancellation timing
- **Policy Administration**: Activate/deactivate policies as needed

#### Room & Property Management

- **Room Categories**: Organize rooms into categories for easier pricing management
- **Room Features**: Track bed types, capacity, descriptions, and images
- **Active/Inactive Rooms**: Enable or disable rooms without deleting them
- **Property Support**: Manage multiple properties (Tahoe cabin, Clear Lake cabin)

#### Check-In & Access Management

- **Digital Check-In**: Track check-ins with rules agreement and timestamp
- **Vehicle Registration**: Associate vehicles with check-ins for property access
- **Door Code Management**: Rotate door codes with active date ranges
- **Automatic Door Code Delivery**: Send current door codes to guests before check-in

#### Booking Lifecycle

- **Draft → Hold → Complete Flow**: Multi-step booking process with inventory holds
- **Automatic Hold Expiry**: Release inventory if payment isn't completed in time
- **Payment Integration**: Seamless Stripe integration for payment processing
- **Confirmation Emails**: Automated booking confirmations with details and receipts
- **Reminder System**: Automated check-in and checkout reminders via email and SMS

#### Inventory Management

- **Real-Time Availability**: Track room and property availability across date ranges
- **Conflict Prevention**: Prevent double-bookings with inventory locking
- **Booking Holds**: Temporarily reserve inventory during checkout process
- **Multi-Room Bookings**: Support bookings spanning multiple rooms simultaneously

**Related Documentation:**

- [Booking System Guide](docs/BOOKING_SYSTEM.md)
- [Pricing Configuration](docs/BOOKING_PRICING.md)
- [Refund Policies](docs/BOOKING_REFUNDS.md)

### Financial Management

Comprehensive financial management tools with accounting integration and automated workflows:

#### Payment Processing

- **Stripe Integration**: Full payment lifecycle management
  - Credit card payments with PCI compliance
  - Automated refund processing
  - Dispute handling and management
  - Subscription and recurring billing
  - Payment method updates

#### Expense Report System

A complete expense and income tracking system with QuickBooks integration:

##### Report Creation & Management

- **Dual-Purpose Reports**: Track both expenses (money spent) and income (money received) in a single report
- **Expense Items**: Line-item tracking with required fields
  - Date, vendor, description, amount
  - Mandatory receipt uploads (stored securely in S3)
  - Receipt validation before submission
- **Income Items**: Track revenue and reimbursements
  - Date, description, amount
  - Optional proof-of-payment attachments
- **Event Association**: Optionally link reports to specific events for better organization
- **Draft & Submission Flow**: Save drafts and submit when ready

##### Reimbursement Options

- **Check Reimbursement**: Request payment via physical check
  - Requires mailing address on file
  - Address validation before submission
- **Bank Transfer (ACH)**: Direct deposit to bank account
  - Secure encrypted bank account storage (Cloak encryption)
  - Routing number validation with checksum verification
  - Only last 4 digits displayed (PCI-like security)
  - Bank account ownership validation

##### Bank Account Security

- **Encrypted Storage**: Routing and account numbers encrypted at rest using Cloak.Ecto
- **Minimal Exposure**: Sensitive data never logged or serialized to JSON
- **Safe Display**: Only last 4 digits shown in UI
- **One Account Per User**: Users can store one bank account for reimbursements
- **Explicit Decryption**: Sensitive fields only decrypted when absolutely necessary

##### Status Workflow

- **Draft**: Initial state, can be edited
- **Submitted**: Awaiting treasurer review, triggers QuickBooks sync
- **Approved**: Approved by treasurer
- **Rejected**: Requires revision
- **Paid**: Reimbursement processed

##### QuickBooks Integration

- **Automatic Bill Creation**: Submitted reports automatically create QuickBooks bills
  - Vendor creation/lookup for each user
  - Line items mapped to expense categories
  - Receipt attachments uploaded to QuickBooks
- **Idempotent Sync**: Duplicate prevention with bill ID tracking
  - Once synced, never creates duplicate bills
  - Retry-safe with status tracking
- **Async Processing**: Background workers (Oban) for reliable sync
  - Primary sync worker for new submissions
  - Backup sweep worker to catch any missed reports
  - Automatic retry on transient failures
- **Webhook Integration**: QuickBooks webhooks update payment status
  - Bill payment notifications automatically mark reports as "paid"
  - Real-time status updates
- **Sync Status Tracking**: Monitor sync progress
  - Pending, synced, error states
  - Last sync attempt timestamp
  - Error messages for troubleshooting

##### Notifications & Confirmations

- **User Confirmation**: Email sent to user upon submission with report summary
- **Treasurer Notification**: Email alert to treasurer with report details and review link
- **Payment Confirmation**: Automatic notification when marked as paid

##### File Management

- **S3 Storage**: Receipts stored in AWS S3 with secure access
- **Direct Upload**: Client-side uploads with presigned URLs
- **Multiple Format Support**: PDF, images (JPEG, PNG), and common document formats
- **File Download**: Secure signed URLs for accessing uploaded receipts
- **Attachment Tracking**: S3 paths stored with each line item

##### Validation & Requirements

- **Pre-Submission Validation**: All expense items must have receipts before submission
- **Certification Requirement**: Users must accept certification statement before submitting
- **Money Validation**: All amounts must be positive USD values
- **Field Validation**: Required fields enforced (date, vendor, description, amount)
- **Ownership Validation**: Users can only access their own reports

##### Startup Scheduler

- **Automatic Recovery**: On application start, schedules backup sync job
- **Catch Missed Syncs**: Finds any submitted reports not yet synced to QuickBooks
- **Resilient**: Ensures no reports slip through even after server restarts

**Related Documentation:**

- [Financial Management Guide](docs/FINANCIAL_MANAGEMENT.md)
- [Expense Report System](docs/EXPENSE_REPORTS.md)
- [QuickBooks Integration](docs/QUICKBOOKS_INTEGRATION.md)
- [Stripe Integration Guide](docs/STRIPE_INTEGRATION.md)

#### Ledger System

- **Transaction History**: Maintain detailed financial records for all transactions
- **Reconciliation Tools**: Match and verify financial transactions across systems
- **Audit Trail**: Complete history of all financial operations

### Communication & Notifications

A comprehensive multi-channel notification system with user preference controls and robust delivery:

#### Email System

- **40+ Email Templates**: Pre-built templates for every user interaction
  - Account management (registration, password reset, email changes)
  - Membership lifecycle (payment confirmations, renewals, reminders)
  - Bookings (confirmations, reminders, cancellations, refunds)
  - Events (ticket purchases, refunds, event notifications)
  - Volunteers & conduct reports
  - Admin notifications (applications, treasurer alerts, board notifications)
- **MJML-Based Templates**: Responsive email design using MJML framework for consistent rendering across all email clients
- **Template Inheritance**: Shared header, footer, and base layout components for brand consistency
- **Asynchronous Delivery**: All emails processed via Oban background jobs for reliability and performance
- **Idempotency Protection**: Prevents duplicate emails using unique idempotency keys per message
- **Development Mailbox**: Preview all emails at `/dev/mailbox` during development without sending real emails

#### SMS System (Flowroute Integration)

- **SMS Templates**: Text message versions of critical notifications
  - Booking check-in reminders (3 days before arrival with door codes)
  - Two-factor authentication codes
  - Security alerts (password changes, email changes)
  - Phone number verification
- **Flowroute Integration**: Enterprise SMS provider for reliable message delivery
- **Phone Number Validation**: Automatic validation and normalization of North American phone numbers (E.164 format)
- **Delivery Receipts**: Track SMS delivery status and failures
- **Inbound SMS Support**: Receive and process incoming SMS messages
- **SMS Categories**: Organized template categories (account, security, event)

#### User Notification Preferences

- **Granular Controls**: Users can control notification preferences by category
  - Email Categories: Account (required), Event (optional), Newsletter (optional)
  - SMS Categories: Account notifications (optional), Event notifications (optional)
  - Security SMS: Always sent regardless of preferences (2FA, verification codes)
- **Per-User Settings**: Individual preference management in user settings
- **Preference Enforcement**: System automatically respects user preferences before sending
- **Phone Number Management**: Users can add/remove phone numbers for SMS notifications

#### Automated Reminder System

- **Scheduled Reminders**: Oban-powered cron jobs for time-based notifications
  - **Booking Check-in Reminders**: Sent 3 days before arrival at 8:00 AM PST (email + SMS)
  - **Booking Check-out Reminders**: Sent on check-out day (email)
  - **Membership Payment Reminders**: 30-day and 7-day warnings before expiration
- **Conditional Delivery**: Reminders only sent if conditions are still valid (e.g., booking not cancelled)
- **Multi-Channel**: Critical reminders sent via both email and SMS for higher engagement

#### Notification Infrastructure

- **Queue-Based Processing**: Separate Oban queues for emails (`mailers`) and SMS for isolation and scaling
- **Retry Logic**: Automatic retry with exponential backoff for failed deliveries (up to 3 attempts)
- **Logging & Monitoring**: Comprehensive logging of all notification attempts, successes, and failures
- **Template Routing**: Dynamic template resolution based on template names
- **Variable Interpolation**: Rich data passing to templates for personalization
- **Category Mapping**: Automatic categorization of templates for preference enforcement

#### Email Infrastructure (Swoosh)

- **Swoosh Mailer**: Production-ready email delivery using Swoosh library
- **Multiple Adapters**: Support for various SMTP providers and services
- **Email Composition**: HTML and plain-text versions for all transactional emails
- **From Address Configuration**: Configurable sender addresses (info@, membership@, admin@, etc.)
- **Testing Support**: Local adapter for development with in-memory storage

#### Message Tracking & Audit

- **Message History**: Database records of all sent emails and SMS
- **Idempotency Tracking**: Prevents duplicate sends using database-backed deduplication
- **Delivery Status**: Track delivery confirmations from Flowroute for SMS
- **Template Metadata**: Store template name, variables, and rendered content for audit trails

**Related Documentation:**

- [Email System Guide](docs/EMAIL_SYSTEM.md)
- [SMS Integration Guide](docs/SMS_INTEGRATION.md)
- [Notification Preferences](docs/USER_PREFERENCES.md)
- [Template Development](docs/EMAIL_TEMPLATES.md)

### Support

A ticketing system for handling user inquiries and support requests.

**Related Documentation:**

- [Support System Guide](docs/SUPPORT_SYSTEM.md)

### File Management

Uploading and managing files with AWS S3 integration.

**Related Documentation:**

- [File Storage Guide](docs/FILE_STORAGE.md)

### Search

A comprehensive search functionality across the application.

**Related Documentation:**

- [Search Implementation Guide](docs/SEARCH.md)

## Contributing

Contributions to this project are managed by the web tech group. Here's the general workflow for making changes:

1.  **Create a branch**: Create a new branch from `main` for your feature or bug fix. Use a descriptive name (e.g., `feature/add-dark-mode` or `fix/login-bug`).
2.  **Make your changes**: Implement your changes, following the project's coding style and conventions.
3.  **Write tests**: Add tests to cover any new functionality or bug fixes.
4.  **Run preflight checks**: Before committing, run `make preflight` to ensure all CI checks pass locally.
5.  **Submit a pull request**: Open a pull request from your branch to the `main` branch. Provide a clear description of your changes and why they are needed.
6.  **Link ticket**: If you have been assigned a ticket from Linear (webtech team) reference the ticket in your PR description.

A team member will review your pull request. Thank you for your contribution!

### Before You Commit

**Always run `make preflight` before pushing your code!** This command runs all the same checks that will run in CI (GitHub Actions), catching issues early:

```bash
make preflight
```

This single command will:

- Compile your code with warnings as errors
- Check code formatting
- Lint shell scripts (ShellCheck + shfmt)
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
  - Lints shell scripts (ShellCheck + shfmt)
  - Runs Credo in strict mode
  - Runs Sobelow security audit
  - Audits dependencies for vulnerabilities
  - Runs complete test suite with coverage
  - If all checks pass, your code is ready to push to CI

#### Code Quality

- **`make format`** - Format Elixir code and shell scripts
- **`make lint`** - Run the full lint suite:
  - Runs Credo for code analysis
  - Checks that all files are properly formatted
  - Lints shell scripts (ShellCheck + shfmt)
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
- `EMAIL_MEMBERSHIP` - Membership-related email address (defaults to "memberships@ysc.org")
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

## License

This project is licensed under the **Non-Profit Open Software License (NPOSL) 3.0**.

### What This Means

The NPOSL 3.0 is a modern, professionally-written open source license designed specifically for non-profit organizations. It provides:

**✅ You Can:**

- Use, modify, and distribute this software freely
- Create derivative works based on this software
- Deploy the software on networks and servers
- Access and modify the complete source code

**📋 You Must:**

- Keep the source code open and available
- License any derivative works under NPOSL 3.0
- Retain copyright and attribution notices
- Treat network deployment (SaaS) as distribution (no "ASP loophole")

**❌ Restrictions:**

- **Only non-profit organizations** can distribute this software
- Commercial use requires the standard OSL 3.0 license instead
- Trademark and patent rights are reserved

### Why NPOSL 3.0?

According to the license author, Lawrence Rosen: _"Some licensors are non-profit organizations that derive no revenue whatsoever from the distribution of the Original Work or Derivative Works, or even from support or services associated with those works."_

The NPOSL 3.0 is identical to the Open Software License (OSL 3.0) but with Section 17 amendments that:

- Disclaim the "Warranty of Provenance" for non-profits
- Extend liability limitations to include direct damages
- Require the licensor to be a non-profit organization

This license ensures the software remains open source while recognizing the resource constraints of non-profit organizations.

### Full License Text

See the [LICENSE](LICENSE) file for the complete license text.

### Commercial Use

If you represent a for-profit organization and wish to use, modify, or distribute this software, you should contact the project maintainers about licensing under OSL 3.0 or a commercial license instead.
