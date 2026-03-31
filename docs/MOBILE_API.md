# YSC Mobile API Documentation

Base URL: `https://ysc.org/api/v1/mobile` (production) or `http://localhost:4000/api/v1/mobile` (development)

## Authentication

All endpoints require Bearer token authentication. Include the header:

```
Authorization: Bearer <KIOSK_API_KEY>
```

The API key is configured via the `KIOSK_API_KEY` environment variable. Contact the YSC admin to obtain the key.

**Error responses (401 Unauthorized):**
- Missing `Authorization` header → `{"error": "Missing authorization token"}`
- Invalid token → `{"error": "Invalid authorization token"}`

---

## Endpoints

### GET /bookings

List bookings for a property, optionally filtered by date range.

**Query parameters:**

| Parameter    | Required | Description                                      |
|-------------|----------|--------------------------------------------------|
| `property`  | Yes      | `tahoe` or `clear_lake`                          |
| `start_date`| No       | ISO 8601 date (e.g. `2025-03-17`)                |
| `end_date`  | No       | ISO 8601 date                                    |

**Example:** `GET /api/v1/mobile/bookings?property=tahoe&start_date=2025-03-01&end_date=2025-03-31`

**Response (200 OK):**

```json
{
  "data": [
    {
      "id": "01HXYZ...",
      "reference_id": "BK-ABC123",
      "property": "tahoe",
      "status": "complete",
      "checkin_date": "2025-03-15",
      "checkout_date": "2025-03-17",
      "guests_count": 4,
      "children_count": 0,
      "checked_in": true,
      "booking_mode": "buyout",
      "member": {
        "id": "01HXYZ...",
        "first_name": "Jane",
        "last_name": "Doe",
        "email": "jane@example.com",
        "avatar_url": "https://fly.storage.tigris.dev/avatars/01HXYZ.../profile.webp"
      },
      "rooms": [
        { "id": "01HXYZ...", "name": "Master Bedroom" }
      ],
      "guests": [
        {
          "id": "01HXYZ...",
          "first_name": "Jane",
          "last_name": "Doe",
          "is_primary": true
        }
      ],
      "check_ins": [
        {
          "id": "01HXYZ...",
          "checked_in_at": "2025-03-15T14:30:00Z",
          "rules_agreed": true,
          "vehicles": [
            {
              "id": "01HXYZ...",
              "type": "sedan",
              "color": "blue",
              "make": "Toyota"
            }
          ]
        }
      ]
    }
  ]
}
```

**Field reference:**

| Field          | Type    | Description |
|----------------|---------|-------------|
| `member`       | object  | The YSC member who made the booking. `null` if no user linked. |
| `member.avatar_url` | string | Full URL to the member's profile picture. When the member has uploaded a custom avatar (or one was synced from Google/Facebook), this points to an optimized WebP image on our CDN. Otherwise falls back to a country-based default image (same as the website). Load this URL directly in an `<img>` or image component. |
| `status`       | string  | `draft`, `hold`, `complete`, `refunded`, or `canceled` |
| `booking_mode` | string  | `room`, `day`, or `buyout` |
| `checked_in`   | boolean | Whether the guest has completed check-in |

---

### GET /bookings/calendar

Calendar view: bookings grouped by date. Each date in the range lists the bookings that overlap that day.

**Query parameters:**

| Parameter    | Required | Description                                      |
|-------------|----------|--------------------------------------------------|
| `property`  | Yes      | `tahoe` or `clear_lake`                          |
| `start_date`| No       | ISO 8601 date. Default: today                    |
| `end_date`  | No       | ISO 8601 date. Default: 30 days from today       |

**Example:** `GET /api/v1/mobile/bookings/calendar?property=tahoe&start_date=2025-03-01&end_date=2025-03-31`

**Response (200 OK):**

```json
{
  "data": {
    "2025-03-15": [
      {
        "id": "01HXYZ...",
        "reference_id": "BK-ABC123",
        "property": "tahoe",
        "status": "complete",
        "checkin_date": "2025-03-15",
        "checkout_date": "2025-03-17",
        "guests_count": 4,
        "children_count": 0,
        "checked_in": true,
        "booking_mode": "buyout",
        "member": {
          "id": "01HXYZ...",
          "first_name": "Jane",
          "last_name": "Doe",
          "email": "jane@example.com",
          "avatar_url": "https://fly.storage.tigris.dev/avatars/01HXYZ.../profile.webp"
        },
        "rooms": [...],
        "guests": [...],
        "check_ins": [...]
      }
    ],
    "2025-03-16": [...]
  },
  "start_date": "2025-03-01",
  "end_date": "2025-03-31"
}
```

The `data` object maps date strings (ISO 8601) to arrays of booking objects. Each booking has the same structure as in the index endpoint, including `member.avatar_url` for the profile picture (stored avatar or country-based default).

---

### GET /bookings/lookup

Look up bookings by guest or member last name.

**Query parameters:**

| Parameter   | Required | Description                                      |
|-------------|----------|--------------------------------------------------|
| `last_name` | Yes      | Guest or member last name (case-insensitive)     |
| `property`  | No       | `tahoe` or `clear_lake`. Default: `tahoe`        |

**Example:** `GET /api/v1/mobile/bookings/lookup?last_name=Doe&property=tahoe`

**Response (200 OK):** Same structure as `GET /bookings` index.

**Error responses:**
- 422 when `last_name` is missing or blank → `{"error": "last_name is required"}`

---

### GET /properties/:property/info

Property information: rules, check-in/check-out instructions, and active notices.

**Path parameter:** `property` — `tahoe` or `clear_lake`

**Example:** `GET /api/v1/mobile/properties/tahoe/info`

**Response (200 OK):**

```json
{
  "property": "tahoe",
  "settings": { ... },
  "static_info": {
    "name": "Lake Tahoe Cabin",
    "check_in_time": "3:00 PM",
    "check_out_time": "11:00 AM",
    "rules_categories": [...],
    "rules": { ... }
  },
  "rooms": [...],
  "active_door_code": "1234"
}
```

---

### POST /check-in

Perform check-in for one or more bookings.

**Request body (JSON):**

| Field         | Type    | Required | Description |
|---------------|---------|----------|-------------|
| `property`    | string  | Yes      | `tahoe` or `clear_lake` |
| `booking_ids` | array   | Yes      | List of booking IDs or reference IDs (e.g. `["BK-ABC123"]`) |
| `rules_agreed`| boolean | Yes      | Must be `true` |
| `vehicles`    | array   | No       | List of vehicle objects |

**Vehicle object:** `{ "type": "sedan", "color": "blue", "make": "Toyota" }`

**Example request:**

```json
{
  "property": "tahoe",
  "booking_ids": ["BK-ABC123"],
  "rules_agreed": true,
  "vehicles": [
    { "type": "sedan", "color": "blue", "make": "Toyota" }
  ]
}
```

**Response (201 Created):** Check-in record with linked bookings and vehicles.

---

## Profile pictures (`avatar_url`)

The `member.avatar_url` field in booking responses is a full URL you can load directly.

**Avatar sources (in priority order):**

1. **Uploaded avatar:** If the member has uploaded a profile picture (or one was synced from their Google/Facebook login), the URL points to an optimized WebP image on our CDN. Multiple sizes are generated (50×50 thumbnail, 200×200 profile, 500×500 large); the API returns the profile-size variant.
2. **Country default:** If the member has no custom avatar, a country-based default image hosted on ysc.org is used (determined by the member's most connected Nordic country).

Use it in your UI like any image URL:

```html
<img src="{member.avatar_url}" alt="Profile" />
```

No authentication is needed to fetch the image; both the CDN-hosted avatars and the default images are publicly accessible.
