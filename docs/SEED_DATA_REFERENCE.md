# Development Seed Data Reference

## Overview

When you run `make dev-setup`, the database is automatically populated with test data to help you start development immediately. This document provides a complete reference of all seeded data.

## Quick Reference

### Default Admin Account

**Email**: `admin@ysc.org`  
**Password**: `very_secure_password`  
**Role**: Admin  
**State**: Active

This account has full administrative access and is used for testing admin features.

## Complete Seed Data

### Users

The seed creates several types of users to test different scenarios:

#### 1. Admin User

- **Email**: `admin@ysc.org`
- **Password**: `very_secure_password`
- **Role**: Admin
- **State**: Active
- **Name**: Admin User
- **Phone**: +14159009009
- **Membership Type**: Family
- **Date of Birth**: 1980-01-15

#### 2. Active Members (10 users)

Active members with approved applications:

- **Email Pattern**: `firstname_lastname_N@ysc.org`
  - Examples: `karl_andersson_0@ysc.org`, `erik_johansson_1@ysc.org`
- **Password**: `very_secure_password` (all users)
- **Role**: Member
- **State**: Active
- **Membership Types**: Mix of single and family (alternating)
- **Countries**: Random from Sweden, Norway, Denmark, Finland, Iceland

**List of some seeded active users**:
- `karl_andersson_0@ysc.org`
- `erik_johansson_1@ysc.org`
- `lars_karlsson_2@ysc.org`
- `anders_nilsson_3@ysc.org`
- And 6 more...

#### 3. Pending Members (5 users)

Users awaiting membership approval:

- **State**: Pending Approval
- **Email Pattern**: Same as active members
- **Password**: `very_secure_password`
- Used for testing the membership approval workflow

#### 4. Rejected Applications (3 users)

Rejected membership applications:

- **State**: Rejected
- **Password**: `very_secure_password`
- Useful for testing rejection flows and notifications

#### 5. Deleted Users (2 users)

Users who have been deleted:

- **State**: Deleted
- For testing deleted user scenarios

### User Notes

Random notes are added to users to test the notes feature:

- **General notes** (70% of notes): Positive interactions, event attendance, inquiries
- **Violation notes** (30% of notes): Policy violations, behavioral issues
- **Per user**: 2-4 notes randomly generated
- **Categories**: "general" or "violation"

Example notes:
- "User contacted support about membership renewal"
- "Attended the annual summer event in 2024"
- "Violated cabin booking cancellation policy"

### Posts

5 sample blog posts are created:

1. **Welcome to the Young Scandinavians Club**
   - Introduction post for new members
   - Marked as featured post

2. **Annual Midsummer Celebration Coming Up**
   - Event announcement with traditional activities

3. **Scandinavian Cooking Class: Traditional Recipes**
   - Workshop announcement

4. **Hiking Trip to Yosemite National Park**
   - Outdoor activity announcement

5. **Nordic Book Club: February Selection**
   - Book discussion event

All posts include:
- Images from seed assets
- Published state
- Preview text
- Timestamps

### Events

The seed creates a mix of past and upcoming events to test various features:

#### Past Events (4 events)

1. **Past Midsummer Celebration 2023**
   - Date: June 21, 2023
   - Free event (150 spots)

2. **Past Nordic Christmas Dinner**
   - Date: December 15, 2023
   - Paid event: $65 (members) / $85 (regular)

3. **Past Fika Social Hour**
   - Date: November 10, 2023
   - Free event (30 spots)

4. **Past Viking History Lecture**
   - Date: October 5, 2023
   - Free event (40 spots)

#### Upcoming Events (7 events)

1. **Scandinavian Cultural Evening**
   - +30 days from now
   - Free event (100 spots)

2. **Nordic Book Discussion**
   - +45 days from now
   - Free event (25 spots)

3. **Scandinavian Gala Dinner**
   - +60 days from now
   - Paid: $75 (early bird) / $100 (regular)

4. **Wine Tasting: Scandinavian Varietals**
   - +75 days from now
   - Paid: $45 (members) / $60 (non-members)

5. **Summer Festival 2024**
   - +90 days from now
   - Mixed: Free (300), VIP $150 (100), Family $200 (50)

6. **Hiking Day Trip: Marin Headlands**
   - +50 days from now
   - Mixed: Free (15), With Lunch $25 (15)

7. **Language Exchange Meetup**
   - +20 days from now
   - Free event (50 spots)

**Event Features**:
- All events have locations with coordinates
- Event agendas with time-based items
- Ticket tiers (free, paid, or mixed)
- Various capacities and restrictions

### Tahoe Cabin Rooms

8 rooms are created for the Tahoe property:

| Room | Type | Capacity | Beds | Description |
|------|------|----------|------|-------------|
| Room 1 | Standard | 2 | 2 single | Two single beds |
| Room 2 | Standard | 2 | 1 queen | Queen bed |
| Room 3 | Standard | 2 | 1 queen | Queen bed |
| Room 4 | Family | 5 | 1 queen, 3 single | Family room (min 2 guests) |
| Room 5a | Single | 1 | 1 single | Solo traveler |
| Room 5b | Single | 1 | 1 single | Solo traveler |
| Room 6 | Standard | 3 | 1 queen, 1 single | Three guests |
| Room 7 | Standard | 2 | 1 queen | Queen bed |

**Additional room data**:
- Room images (from `priv/static/images/tahoe/`)
- Active status
- Minimum billable occupancy
- Default summer season
- Room categories (single, standard, family)

### Refund Policies

Two refund policies are created for Tahoe:

#### 1. Full Cabin (Buyout) Policy

- **Less than 14 days**: 0% refund (100% forfeiture)
- **Less than 21 days**: 50% refund (50% forfeiture)
- **21+ days**: 100% refund

#### 2. Room Booking Policy

- **Less than 7 days**: 0% refund (100% forfeiture)
- **Less than 14 days**: 50% refund (50% forfeiture)
- **14+ days**: 100% refund

### Site Settings

Social media links are configured:

- **Instagram**: https://www.instagram.com/theysc
- **Facebook**: https://www.facebook.com/YoungScandinaviansClub/
- **Discord**: https://discord.gg/dn2gdXRZbW

### Images

Images are uploaded to S3 from `etc/seed/assets/`:

- Blog post feature images
- Event images
- Room images for Tahoe rooms
- All images are processed (thumbnails, optimized versions, blur hash)

## Testing Common Scenarios

### Login as Admin

```
Email: admin@ysc.org
Password: very_secure_password
```

### Login as Regular Member

```
Email: karl_andersson_0@ysc.org
Password: very_secure_password
```

### Test Membership Approval Workflow

1. Login as admin
2. Navigate to admin panel
3. View pending members
4. Approve/reject applications

### Test Event Registration

1. Login as any member
2. Browse to upcoming events
3. Register for free events
4. Purchase tickets for paid events
5. View agendas and event details

### Test Cabin Booking

1. Login as active member
2. Navigate to Tahoe booking
3. Browse available rooms
4. Make test booking
5. Test cancellation policies

### Test User Notes

1. Login as admin
2. View any user's profile
3. See existing notes (general and violation)
4. Add new notes

## Resetting Seed Data

To reset the database and reseed:

```bash
# Drop database
make reset-db

# Recreate and seed
make setup-dev-db
```

**Note**: This will destroy all data and recreate from seed files.

## Seed Files

The seed data is defined in:

- **`priv/repo/seeds.exs`** - Main seed file (users, posts, events, etc.)
- **`priv/repo/seeds_bookings.exs`** - Booking-specific seeds (rooms, seasons, prices)
- **`etc/seed/assets/`** - Image files for posts and events
- **`priv/static/images/tahoe/`** - Room images for Tahoe cabin

## Important Notes

### Passwords

All seeded users share the same password: **`very_secure_password`**

This is intentional for easy testing. **Never use these credentials in production.**

### Email Addresses

All email addresses use `@ysc.org` domain and follow predictable patterns. This makes it easy to:
- Remember login credentials
- Test email features (they'll appear in `/dev/mailbox`)
- Distinguish between seeded and real users

### Data Persistence

Seeded data persists across:
- ✅ Phoenix server restarts
- ✅ Docker container restarts (as long as volumes persist)
- ❌ Database drops (`make reset-db`)
- ❌ Docker volume removal

### Modifying Seed Data

To customize seed data:

1. Edit `priv/repo/seeds.exs`
2. Run `make reset-db && make setup-dev-db`
3. New seed data will be created

## Testing Tips

### Use Different User Types

Test features with different user roles:
- **Admin**: Full access, can approve members, manage content
- **Active Member**: Standard access, can book cabins, register for events
- **Pending Member**: Limited access, awaiting approval
- **Rejected Member**: Cannot access member features

### Test with Family Members

Some seeded users have family memberships with spouse and children. Test:
- Family member management
- Family-rate tickets
- Multiple occupancy bookings

### Test Historical Data

Past events allow you to test:
- Event archive views
- Historical reporting
- "Past events" filters
- Event attendance tracking

## Production Seeds

For production, use `priv/repo/seeds_prod.exs`:

```bash
mix run priv/repo/seeds_prod.exs
```

**Production seeds create**:
- Admin user with environment-based password
- Essential site settings
- No test data

**Never run development seeds in production!**

---

**Last Updated**: 2026-02-04  
**Purpose**: Reference for all seeded development data  
**Status**: Complete ✅
