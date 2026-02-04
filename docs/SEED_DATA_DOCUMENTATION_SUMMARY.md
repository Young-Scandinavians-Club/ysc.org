# Seed Data Documentation - Summary

## Overview

Added comprehensive documentation about the development seed data, including default login credentials and all test data that gets created when running `make dev-setup`.

## Problem Solved

New developers needed to know:
- How to log in to the application after setup
- What test data is available
- How to test different features with seeded data
- User credentials for testing different roles

## Documentation Added

### 1. README.md - "Seeded Development Data" Section

**Location**: After "Initial Setup" section

**Content**:
- Default admin credentials prominently displayed
- List of all seeded data types:
  - Active members (10)
  - Pending members (5)
  - Rejected applications (3)
  - User notes
  - Sample posts
  - Sample events (past and upcoming)
  - Tahoe cabin rooms
  - Social media links
- Pattern for other user emails
- Note that all passwords are the same

### 2. QUICKREF.md - "Default Login Credentials" Section

**Location**: Under "Daily Development Workflow"

**Content**:
- Admin credentials prominently shown
- Quick reference for starting development
- Pattern for test user emails

### 3. docs/SEED_DATA_REFERENCE.md (NEW)

**Purpose**: Complete reference for all seed data

**Content**:

#### Quick Reference
- Default admin account details

#### Complete Seed Data
- **Users**: Admin, active members, pending, rejected, deleted
  - Full list with email patterns
  - All user details (role, state, membership type)
  
- **User Notes**: General and violation notes
  - Examples of each type
  - Distribution (70% general, 30% violation)
  
- **Posts**: 5 blog posts
  - Titles and descriptions
  - Featured post indication
  
- **Events**: 11 events total
  - 4 past events
  - 7 upcoming events
  - Free, paid, and mixed ticket types
  - Complete details with dates and pricing
  
- **Tahoe Cabin Rooms**: 8 rooms
  - Complete table with capacities and bed types
  - Room categories
  - Images and features
  
- **Refund Policies**: 2 policies
  - Full cabin (buyout) policy with rules
  - Room booking policy with rules
  
- **Site Settings**: Social media links

- **Images**: Uploaded from seed assets

#### Testing Scenarios
- How to test different user types
- Common workflows to test
- Feature testing with seed data

#### Resetting Data
- Commands to reset and reseed
- Warning about data loss

#### Seed Files Reference
- Location of all seed files
- Purpose of each file

#### Important Notes
- Password security warning
- Email address patterns
- Data persistence rules
- Production seeds info

### 4. docs/NEW_DEVELOPER_GUIDE.md - Updates

**Added**:
- Reference to SEED_DATA_REFERENCE.md in documentation organization
- Default login credentials section
- Link to full seed data reference

## Key Information

### Default Admin Account

```
Email: admin@ysc.org
Password: very_secure_password
```

**This is now prominently displayed in:**
- README.md (setup section)
- QUICKREF.md (daily workflow section)
- NEW_DEVELOPER_GUIDE.md (essential commands section)
- SEED_DATA_REFERENCE.md (quick reference section)

### Other Test Users

All seeded users share the same password: `very_secure_password`

Email pattern: `firstname_lastname_N@ysc.org`

Examples:
- `karl_andersson_0@ysc.org`
- `erik_johansson_1@ysc.org`
- `lars_karlsson_2@ysc.org`

### Quick Access

New developers can:
1. Run `make dev-setup`
2. Visit http://localhost:4000
3. Log in with `admin@ysc.org` / `very_secure_password`
4. Start testing immediately

## Benefits

1. **Immediate access** - Developers know exactly how to log in
2. **No guessing** - All credentials clearly documented
3. **Complete reference** - Full details on all test data
4. **Easy testing** - Know what data is available for testing
5. **Time saving** - Don't need to create test data manually
6. **Multiple scenarios** - Can test different user types and states
7. **Realistic data** - Events, posts, bookings pre-populated

## Testing Workflows Enabled

With documented seed data, developers can now easily test:

### User Management
- Admin approval workflows (5 pending users ready)
- User notes (pre-populated on users)
- Different user states (active, pending, rejected, deleted)
- Family memberships (some users have family members)

### Events
- Event listing (past and upcoming)
- Event registration (free events)
- Ticket purchasing (paid events)
- Event agendas (all events have agendas)
- Mixed ticket types (free + paid options)

### Cabin Bookings
- Room browsing (8 Tahoe rooms with images)
- Booking flow (different room types)
- Cancellation policies (2 policies configured)
- Capacity constraints (single, standard, family rooms)

### Content
- Blog posts (5 sample posts)
- Images (uploaded to S3)
- Social media integration (links configured)

## Usage Pattern

Typical developer workflow:

```bash
# Day 1: Setup
make dev-setup  # Creates all seed data

# Day 1: First login
Email: admin@ysc.org
Password: very_secure_password

# Day 2+: Reference seed data
Check docs/SEED_DATA_REFERENCE.md for:
- Available test users
- Sample events to test
- Rooms to book
- etc.
```

## Important Notes

### Security

All documentation includes warnings:
- **Never use these credentials in production**
- Passwords are intentionally simple for development only
- All emails use test domain (@ysc.org)

### Data Persistence

Clearly documented:
- ✅ Persists across Phoenix restarts
- ✅ Persists across Docker restarts (if volumes preserved)
- ❌ Lost on `make reset-db`
- ❌ Lost on Docker volume removal

### Customization

Documented how to:
- Modify seed data (edit seeds.exs)
- Reset and reseed
- Add custom test data

## Documentation Cross-References

All documents link to each other:
- README → SEED_DATA_REFERENCE.md
- QUICKREF → Shows credentials inline
- NEW_DEVELOPER_GUIDE → Links to seed data reference
- SEED_DATA_REFERENCE → Comprehensive standalone doc

## Summary

Seed data documentation now provides:
✅ Default login credentials (admin@ysc.org)
✅ Complete list of all seeded data
✅ How to test different features
✅ Email patterns for test users
✅ Event and room details
✅ How to reset/customize seed data
✅ Security warnings
✅ Cross-referenced in all guides

New developers can now:
- Log in immediately after setup
- Know what test data is available
- Test all features without creating data manually
- Understand different user types and states
- Reference complete seed data documentation

---

**Created**: 2026-02-04  
**Purpose**: Help developers know default credentials and available test data  
**Status**: Complete ✅
