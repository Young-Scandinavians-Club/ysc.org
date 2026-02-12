# Local Development Environment Architecture

This document provides a visual overview of how all the pieces fit together in your local development environment.

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Your Local Machine                              │
│                                                                           │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    Phoenix Application (Port 4000)                 │  │
│  │                                                                     │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │  │
│  │  │  LiveView    │  │ Controllers  │  │  Background  │            │  │
│  │  │  Pages       │  │ & APIs       │  │  Jobs (Oban) │            │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘            │  │
│  │         │                 │                   │                    │  │
│  │         └─────────────────┴───────────────────┘                    │  │
│  │                           │                                         │  │
│  │                  ┌────────▼─────────┐                              │  │
│  │                  │  Core Business   │                              │  │
│  │                  │  Logic (Contexts)│                              │  │
│  │                  └────────┬─────────┘                              │  │
│  │                           │                                         │  │
│  └───────────────────────────┼─────────────────────────────────────────┘  │
│                               │                                            │
│  ┌────────────────────────────┼────────────────────────────────────────┐  │
│  │        Docker Containers   │                                        │  │
│  │                            │                                        │  │
│  │  ┌─────────────────────────▼───────────┐                           │  │
│  │  │     PostgreSQL (Port 5432)          │                           │  │
│  │  │  ┌─────────────────────┐             │                           │  │
│  │  │  │     ysc_dev DB      │             │                           │  │
│  │  │  └─────────────────────┘             │                           │  │
│  │  └─────────────────────────────────────┘                           │  │
│  │           │                                                         │  │
│  │  ┌────────▼────────────────────────────┐                           │  │
│  │  │  LocalStack (Port 4566)             │                           │  │
│  │  │  (Simulates AWS S3 for file upload) │                           │  │
│  │  └─────────────────────────────────────┘                           │  │
│  │           │                                                         │  │
│  │  ┌────────▼────────────────────────────┐                           │  │
│  │  │  PgAdmin (Port 8888)                │                           │  │
│  │  │  (Database management UI)           │                           │  │
│  │  └─────────────────────────────────────┘                           │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │              Stripe CLI (Webhook Forwarding)                       │  │
│  │                                                                     │  │
│  │         stripe listen --forward-to localhost:4000/webhooks/stripe  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                               │                                            │
└───────────────────────────────┼────────────────────────────────────────────┘
                                │
                    ┌───────────▼──────────┐
                    │   Stripe API         │
                    │   (External)         │
                    └──────────────────────┘
```

## Data Flow Examples

### 1. User Creates a Payment

```
Browser → Phoenix LiveView → Stripe.js (client-side) → Stripe API
                                                            │
                      ┌─────────────────────────────────────┘
                      │
                      ▼
            Stripe Webhook Event
                      │
                      ▼
               Stripe CLI (forwards)
                      │
                      ▼
          Phoenix Webhook Controller
                      │
                      ▼
          Process Payment (Business Logic)
                      │
                      ├──► PostgreSQL (save payment record)
                      │
                      ├──► Oban (enqueue QuickBooks sync job)
                      │
                      └──► Email (send confirmation)
```

### 2. User Uploads a File

```
Browser → LiveView Upload → Phoenix Controller
                                    │
                                    ▼
                            S3 Upload Logic
                                    │
                                    ▼
                          LocalStack S3 (local)
                            or AWS S3 (production)
                                    │
                                    ▼
                           Save file URL to PostgreSQL
```

### 3. Background Job Processing

```
Trigger Event → Enqueue Oban Job → PostgreSQL (jobs table)
                                          │
                                          ▼
                                 Oban Worker Polls
                                          │
                                          ▼
                                  Execute Job Logic
                                          │
                          ┌───────────────┼───────────────┐
                          │               │               │
                          ▼               ▼               ▼
                   Update Database   Call API      Send Email
                                   (e.g., Stripe,
                                    QuickBooks)
```

### 4. Newsletter Subscription Flow

```
User subscribes → Phoenix LiveView → Save to YSC DB
                         │
                         ▼
              Update newsletter_subscribers
                         │
                         ▼
              Oban Worker (async processing)
                         │
                         ▼
                   Ysc.Newsletter
                         │
                         ▼
              Save to newsletter_subscribers
```

**Key Points:**
- Newsletter subscriptions are stored in the app database (newsletter_subscribers)
- Subscription status is tracked in the YSC database
- In development, app emails (including any newsletter-related) use Swoosh local adapter and are viewable at /dev/mailbox


## Port Reference

| Service       | Port | URL                              | Purpose                    |
|---------------|------|----------------------------------|----------------------------|
| Phoenix       | 4000 | http://localhost:4000            | Main application           |
| Swoosh Mailbox| 4000 | http://localhost:4000/dev/mailbox| App email preview          |
| PostgreSQL    | 5432 | localhost:5432                   | Database                   |
| LocalStack S3 | 4566 | http://localhost:4566            | Local S3 simulation        |
| PgAdmin       | 8888 | http://localhost:8888            | Database management UI     |

## Environment Files

```
ysc-redesign-ex/
├── .env                    # Your local environment variables (NOT in git)
├── .env.example            # Template for .env (in git)
├── .tool-versions          # Specifies Elixir/Erlang versions
├── config/
│   ├── dev.exs            # Development configuration
│   ├── test.exs           # Test configuration
│   ├── prod.exs           # Production configuration
│   └── runtime.exs        # Runtime configuration (reads .env)
└── etc/docker/
    └── docker-compose.yml  # Docker services configuration
```

## Development Workflow

```
┌──────────────────────────────────────────────────────────────┐
│ 1. Start Docker Services                                      │
│    docker-compose up -d                                       │
│    (automatically done by `make dev-setup`)                   │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│ 2. Start Stripe Webhook Forwarding                            │
│    stripe listen --forward-to localhost:4000/webhooks/stripe  │
│    (keep this running in Terminal 1)                          │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│ 3. Start Phoenix Server                                       │
│    make dev                                                    │
│    (keep this running in Terminal 2)                          │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│ 4. Make Changes                                               │
│    - Edit code in lib/                                        │
│    - Phoenix auto-reloads most changes                        │
│    - Check browser at http://localhost:4000                   │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│ 5. Run Tests                                                  │
│    make test                                                   │
│    (in Terminal 3)                                            │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│ 6. Before Committing                                          │
│    make preflight                                              │
│    (runs all CI checks locally)                               │
└──────────────────────────────────────────────────────────────┘
```

## Key Technologies

### Backend
- **Elixir**: Functional programming language
- **Phoenix**: Web framework
- **Ecto**: Database wrapper and query language
- **Oban**: Background job processing

### Frontend
- **LiveView**: Real-time, server-rendered UI
- **TailwindCSS**: Utility-first CSS framework
- **Alpine.js**: Minimal JavaScript framework (for client-side interactions)

### Database
- **PostgreSQL**: Primary database

### File Storage
- **AWS S3**: Production file storage
- **LocalStack**: Local S3 simulation for development

### External Services
- **Stripe**: Payment processing
- **QuickBooks**: Accounting integration
- **Flowroute**: SMS services
- **Newsletter**: In-house subscription management (Ysc.Newsletter)
  - Open-source newsletter platform
  - Runs locally in Docker for development
  - Manages subscriber lists and campaigns
  - Integrated via API calls from Oban workers

### Development Services (Docker)
- **PostgreSQL**: Database for the YSC app
- **LocalStack**: AWS S3 simulation
- **PgAdmin**: Database management UI

## Understanding the Codebase

```
lib/
├── ysc/                          # Core business logic (contexts)
│   ├── accounts/                 # User accounts and auth
│   ├── bookings/                 # Booking system
│   ├── events/                   # Event management
│   ├── newsletter/               # Newsletter subscriptions
│   │   └── subscriber.ex         # Newsletter subscriber schema
│   ├── ledgers/                  # Financial ledgers
│   ├── memberships/              # Membership management
│   ├── payments/                 # Payment processing
│   ├── quickbooks/               # QuickBooks integration
│   ├── stripe/                   # Stripe integration
│   └── ...
│
├── ysc_web/                      # Web interface
│   ├── components/               # Reusable UI components
│   ├── controllers/              # HTTP controllers
│   ├── live/                     # LiveView pages
│   ├── emails/                   # Email templates
│   ├── workers/                  # Background jobs (Oban)
│   └── ...
│
└── ysc_web.ex                    # Web module definition
```

## Data Flow Principles

1. **Separation of Concerns**:
   - `lib/ysc/` - Business logic (doesn't know about HTTP)
   - `lib/ysc_web/` - Web interface (uses business logic)

2. **Context Pattern**:
   - Related functions grouped in contexts (e.g., `Ysc.Accounts`)
   - Contexts are the public API for business logic

3. **LiveView Pattern**:
   - Server-rendered, real-time updates
   - No need for separate API for most features
   - Minimal JavaScript required

4. **Background Jobs**:
   - Long-running tasks use Oban (e.g., QuickBooks sync)
   - Jobs are persisted in PostgreSQL
   - Automatic retries with exponential backoff

## Common Development Tasks

### Adding a New Feature

```
1. Add business logic
   ├── Create/update context in lib/ysc/
   └── Write tests in test/ysc/

2. Add web interface
   ├── Create LiveView in lib/ysc_web/live/
   ├── Add route in lib/ysc_web/router.ex
   └── Write feature tests in test/ysc_web/live/

3. Test and verify
   ├── Run tests: make test
   ├── Run preflight: make preflight
   └── Manual testing in browser
```

### Debugging

```
1. Use IEx for interactive debugging
   ├── Add IEx.pry() in your code
   └── Run: make dev (or make shell)

2. Check logs
   ├── Phoenix server logs (Terminal 2)
   ├── Stripe CLI logs (Terminal 1)
   └── Docker container logs: docker-compose logs

3. Inspect database
   ├── Use PgAdmin: http://localhost:8888
   └── Or psql: PGPASSWORD=postgres psql -h localhost -U postgres -d ysc_dev
```

### Testing Newsletters

```
1. Subscribe a test email
   ├── Via homepage: http://localhost:4000 (newsletter form)
   ├── Via user settings: Settings → Notifications → Newsletter
   └── Via IEx: Ysc.Newsletter.subscribe("test@example.com")

2. Verify subscription
   ├── Check newsletter_subscribers table
   └── Open /newsletter/unsubscribe/:token for unsubscribe links

3. Check subscription status
   └── In IEx: Ysc.Newsletter.get_subscriber_by_email("test@example.com")
```

**Key Files for Newsletter Integration:**
- `lib/ysc/newsletter.ex` - Newsletter context
- `lib/ysc/newsletter/subscriber.ex` - Subscriber schema
- `lib/ysc_web/live/newsletter_unsubscribe_live.ex` - Public unsubscribe page

### Testing Application Emails

```
1. View all sent emails
   └── Open: http://localhost:4000/dev/mailbox

2. Test registration email
   ├── Register new user: http://localhost:4000/users/register
   └── Check /dev/mailbox for confirmation email

3. Test password reset
   ├── Request reset: http://localhost:4000/users/reset-password
   └── Check /dev/mailbox for reset link

4. Test transactional emails
   ├── Purchase ticket or book event
   ├── Update user settings
   ├── Process payment
   └── Check /dev/mailbox for confirmations
```

**Email in development:**

| System | URL | Purpose |
|--------|-----|---------|
| Swoosh Mailbox | http://localhost:4000/dev/mailbox | App emails (registration, tickets, notifications) |

**Key Email Files:**
- `lib/ysc_web/emails/` - Email templates (MJML)
- `config/config.exs` - Swoosh configuration
- `lib/ysc/mailer.ex` - Email sending logic



## Additional Resources

- **README.md**: Full setup instructions
- **QUICKREF.md**: Quick reference for common commands
- **docs/TROUBLESHOOTING.md**: Detailed troubleshooting guide
- **docs/**: Additional project documentation
