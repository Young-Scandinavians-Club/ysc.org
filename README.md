# Ysc

This is the central repository for the YSC web application, a comprehensive platform for managing club activities, memberships, events, and finances. Built with Elixir and the Phoenix framework, it provides a robust and scalable solution for the club's needs.

## Getting Started

### Prerequisites

- Elixir and Erlang installed
- Docker and Docker Compose installed
- Stripe API keys (see Environment Variables section below)
- Fly.io CLI (optional, for sandbox deployment)

### Initial Setup

### 1. Set Up Environment Variables

### 2. Install Dependencies and Set Up the Database

   ```bash
   make dev-setup
   ```

   This command will:

   - Install dependencies
   - Start local development services (database, S3, etc.)
   - Run database migrations
   - Seed the database with initial data

### 3. Start the Development Server
   ```bash
   make dev
   ```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Deployment & Environments

The application is configured to run in three main environments: development, sandbox, and production.

### Development

The development environment is configured for local development. You can set it up and run it using the `make dev-setup` and `make dev` commands. It runs with hot-reloading enabled.

### Sandbox (Fly.io)

The project includes a sandbox environment deployed on Fly.io for testing integrations in a production-like environment.

#### Sandbox Configuration

-   **URL**: https://ysc-sandbox.fly.dev
-   **Environment**: Sandbox (auto-shuts down after 10 minutes of inactivity)
-   **QuickBooks**: Uses QuickBooks Sandbox API
-   **Stripe**: Uses Stripe test mode

#### Deploying to Sandbox

To deploy changes to the sandbox environment:

```bash
make deploy-sandbox
```

### Production

The production environment is hosted on Fly.io. For detailed deployment instructions, please refer to the official Phoenix deployment guides.

## Architecture

This is a web application built with the Phoenix framework, written in Elixir. It follows the standard Phoenix project structure:

*   **Core Business Logic (`lib/ysc`)**: This layer encapsulates the core functionalities of the application, such as user accounts, payments, bookings, and integrations with third-party services like Stripe and QuickBooks. It is decoupled from the web interface.
*   **Web Interface (`lib/ysc_web`)**: This is the Phoenix web application that provides the user interface. It uses Phoenix LiveView for rich, real-time user experiences, and traditional controllers for handling HTTP requests. It's responsible for rendering templates, handling user input, and communicating with the core business logic.
*   **Database**: The application uses a PostgreSQL database, managed by Ecto, Elixir's database wrapper and query language.
*   **Background Jobs**: Asynchronous tasks, like sending emails or syncing with QuickBooks, are managed by Oban, a robust background job processing library for Elixir.
*   **Third-Party Integrations**:
    *   **Stripe**: For payment processing.
    *   **QuickBooks**: For accounting and financial management.
    *   **AWS S3**: For file storage.
    *   **Flowroute**: For SMS services.

## Features

The application provides a comprehensive set of features for managing a club or organization:

*   **User Management**: User accounts, authentication, and authorization.
*   **Membership Management**: Handling memberships, subscriptions, and renewals.
*   **Event Management**: Creating and managing events, including ticketing and registration.
*   **Bookings**: A system for booking resources or facilities.
*   **Content Management**: Creating and publishing posts and announcements.
*   **Financial Management**:
    *   Processing payments with Stripe.
    *   Generating expense reports.
    *   Syncing financial data with QuickBooks.
    *   Maintaining ledgers and financial records.
*   **Communication**: Sending emails and SMS messages to users.
*   **Support**: A ticketing system for handling user inquiries.
*   **File Management**: Uploading and managing files with AWS S3.
*   **Search**: A comprehensive search functionality.

## Contributing

Contributions to this project are managed by the web tech group. Here's the general workflow for making changes:

1.  **Create a branch**: Create a new branch from `main` for your feature or bug fix. Use a descriptive name (e.g., `feature/add-dark-mode` or `fix/login-bug`).
2.  **Make your changes**: Implement your changes, following the project's coding style and conventions.
3.  **Write tests**: Add tests to cover any new functionality or bug fixes.
4.  **Run tests**: Make sure the entire test suite passes by running `make test`.
5.  **Lint your code**: Ensure your code is well-formatted and free of linting errors by running `make lint`.
6.  **Submit a pull request**: Open a pull request from your branch to the `main` branch. Provide a clear description of your changes and why they are needed.

A team member will review your pull request. Thank you for your contribution!

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

#### Code Quality

- **`make format`** - Format all Elixir code using the project's formatter
- **`make lint`** - Run the full lint suite:
  - Runs Credo for code analysis
  - Checks that all files are properly formatted
  - Use this before committing code

#### Testing

- **`make test`** or **`make tests`** - Run the full test suite
  - Automatically starts PostgreSQL if needed
  - Runs all tests with trace output
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

