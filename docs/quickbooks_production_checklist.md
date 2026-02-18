# QuickBooks Production Setup Checklist

Use this checklist when standing up the production environment for the YSC QuickBooks integration. All accounts and classes must exist in QuickBooks **before** syncing payments, refunds, or payouts. Products/Items can be created by the app if not configured, but each requires a matching **income account** to exist.

---

## 1. Accounts (Chart of Accounts)

Create these accounts in QuickBooks (**Settings → Chart of Accounts**). Account type and usage are noted.

### Required – Revenue / Income (for Sales Receipts and Items)

| Account Name          | Purpose / Used For                          | Notes                                                                                        |
| --------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **Events Inc**        | Event ticket revenue                        | Income/Revenue type. Used as income account for "Event Tickets" item.                        |
| **Donations**         | Donation revenue                            | Income/Revenue type. Used for "Donations" item.                                              |
| **Tahoe Inc**         | Tahoe cabin booking revenue                 | Income/Revenue type. Used for "Tahoe Bookings" item.                                         |
| **Clear Lake Inc**    | Clear Lake cabin booking revenue            | Income/Revenue type. Used for "Clear Lake Bookings" item.                                    |
| **Family Membership** | Family membership revenue                   | Income/Revenue type. Used for "Family Membership" item.                                      |
| **Single Membership** | Single membership revenue                   | Income/Revenue type. Used for "Single Membership" item.                                      |
| **Membership Inc**    | Other membership revenue                    | Income/Revenue type. Used for "Memberships" item.                                            |
| **General Revenue**   | Fallback revenue (optional but recommended) | Income/Revenue type. Used when no specific account matches; also fallback for item creation. |
| **Other Income**      | Fallback (optional)                         | Income/Revenue type. Second fallback for item creation.                                      |
| **Services**          | Fallback (optional)                         | Income/Revenue type. Third fallback for item creation.                                       |

### Required – Expense

| Account Name                            | Purpose / Used For                                     | Notes                                                                                                                                                                        |
| --------------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Stripe Fees**                         | Stripe processing fees on payouts                      | Expense type. Used in Deposit line when recording fee deductions.                                                                                                            |
| **Ticket Discounts**                    | Reserved ticket discount expense                       | Expense type. Used for discount line items on sales receipts.                                                                                                                |
| **Cost of Goods Sold** or **Purchases** | Default expense account for Service/NonInventory items | At least one must exist so the app can create items (e.g. "Event Tickets") when not pre-configured. Config `default_expense_account_name` can override (e.g. `"Purchases"`). |

### Required – Other (Bank / Current Asset)

| Account Name          | Purpose / Used For                              | Notes                                                                                                                                                                   |
| --------------------- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Undeposited Funds** | Sales Receipts and Refund Receipts deposit here | Usually created by QuickBooks by default. Must exist; app does not create it.                                                                                           |
| **Bank account**      | Payout deposits (Stripe → Bank)                 | **Not created by app.** You must create/link your real bank account and set `QUICKBOOKS_BANK_ACCOUNT_ID` to its QuickBooks Account ID.                                  |
| **Stripe settlement** | Source of funds for deposit (entity_ref)        | **Not created by app.** Create an account representing Stripe (e.g. "Stripe" or "Stripe Clearing") and set `QUICKBOOKS_STRIPE_ACCOUNT_ID` to its QuickBooks Account ID. |

---

## 2. Classes (Location / Department Tracking)

Create these **Classes** in QuickBooks (**Settings → All Lists → Classes**). If a class is missing, the app falls back to "Administration" for that transaction.

| Class Name         | Used For                                                                                     |
| ------------------ | -------------------------------------------------------------------------------------------- |
| **Administration** | Donations, memberships, Stripe fees, ticket discounts, fallback for unknown. **Must exist.** |
| **Events**         | Event ticket sales                                                                           |
| **Clear Lake**     | Clear Lake cabin bookings                                                                    |
| **Tahoe**          | Tahoe cabin bookings                                                                         |

---

## 3. Products and Services (Items)

The app can **get-or-create** items by name if the corresponding config env var is not set. Each item **must** have an **Income account** set (either when you create it or so the app can set it from the accounts above). Otherwise QuickBooks returns error 2390.

### Option A – Pre-create items in QuickBooks (recommended for production)

Create these **Service** (or **Non-inventory**) items and set **Income account** per row. Then set the matching env vars so the app uses these IDs.

| Item Name           | Income Account (set in QB) | Config env var                                                                                   |
| ------------------- | -------------------------- | ------------------------------------------------------------------------------------------------ |
| Event Tickets       | Events Inc                 | `QUICKBOOKS_EVENT_ITEM_ID`                                                                       |
| Donations           | Donations                  | `QUICKBOOKS_DONATION_ITEM_ID`                                                                    |
| Tahoe Bookings      | Tahoe Inc                  | `QUICKBOOKS_TAHOE_BOOKING_ITEM_ID`                                                               |
| Clear Lake Bookings | Clear Lake Inc             | `QUICKBOOKS_CLEAR_LAKE_BOOKING_ITEM_ID`                                                          |
| Family Membership   | Family Membership          | `QUICKBOOKS_FAMILY_MEMBERSHIP_ITEM_ID`                                                           |
| Single Membership   | Single Membership          | `QUICKBOOKS_SINGLE_MEMBERSHIP_ITEM_ID`                                                           |
| Memberships         | Membership Inc             | `QUICKBOOKS_MEMBERSHIP_ITEM_ID`                                                                  |
| General Revenue     | General Revenue            | `QUICKBOOKS_DEFAULT_ITEM_ID` (fallback)                                                          |
| (Stripe fee item)   | N/A – expense account      | `QUICKBOOKS_STRIPE_FEE_ITEM_ID` (used for fee line if needed; may be optional depending on flow) |

For **Service** (and **Non-inventory**) items, QuickBooks also requires an **Expense account**. Ensure at least one of **Cost of Goods Sold** or **Purchases** exists (or configure `default_expense_account_name`).

### Option B – Let the app create items

If you do **not** set the item ID env vars, the app will look up an item by the name in the table above and create it if missing. Creation will **fail** unless a suitable **revenue** account exists (the app tries, in order: the preferred account name, then "General Revenue", "Other Income", "Services", "Events Inc", "Donations"). So at minimum, create **General Revenue** (or one of the fallbacks) before relying on auto-creation.

---

## 4. Environment variables (production)

Set these in your production environment (e.g. runtime or secrets). Account and item IDs are the QuickBooks API IDs (e.g. from the URL or API responses).

### Required

- `QUICKBOOKS_BANK_ACCOUNT_ID` – QuickBooks Account ID for the bank account where Stripe payouts are deposited.
- `QUICKBOOKS_STRIPE_ACCOUNT_ID` – QuickBooks Account ID for the Stripe/settlement account (entity_ref on deposit lines).

### Optional (item IDs – use if you pre-create items)

- `QUICKBOOKS_EVENT_ITEM_ID`
- `QUICKBOOKS_DONATION_ITEM_ID`
- `QUICKBOOKS_TAHOE_BOOKING_ITEM_ID`
- `QUICKBOOKS_CLEAR_LAKE_BOOKING_ITEM_ID`
- `QUICKBOOKS_MEMBERSHIP_ITEM_ID`
- `QUICKBOOKS_SINGLE_MEMBERSHIP_ITEM_ID`
- `QUICKBOOKS_FAMILY_MEMBERSHIP_ITEM_ID`
- `QUICKBOOKS_DEFAULT_ITEM_ID`
- `QUICKBOOKS_STRIPE_FEE_ITEM_ID`

### Optional (account name for new items)

- `default_expense_account_name` – e.g. `"Purchases"` if you prefer that over "Cost of Goods Sold" for auto-created items (see `config :ysc, :quickbooks` in config/runtime.exs; not currently set via env in runtime.exs but can be added).

---

## 5. Verification order

1. **Accounts** – Create all revenue, expense, Undeposited Funds, bank, and Stripe accounts.
2. **Classes** – Create Administration, Events, Clear Lake, Tahoe.
3. **Items** – Either pre-create with correct Income (and Expense) accounts and set env vars, or ensure at least "General Revenue" (or another fallback) exists for auto-creation.
4. **Env vars** – Set `QUICKBOOKS_BANK_ACCOUNT_ID` and `QUICKBOOKS_STRIPE_ACCOUNT_ID`; set item ID vars if using pre-created items.
5. Run a test payment/refund/payout sync and confirm Sales Receipts, Refund Receipts, and Deposits appear correctly in QuickBooks.

---

## 6. Reference: code locations

- Account and class mapping: `lib/ysc/quickbooks/sync.ex` – `@account_class_mapping`, `determine_income_account_name`, `determine_item_name`, `query_income_account`.
- Item creation and income account: `lib/ysc/quickbooks/client.ex` – `get_or_create_item`, `ensure_expense_account_ref_for_item`, `update_item_income_account`.
- Config keys and env vars: `config/runtime.exs` – `config :ysc, :quickbooks`.
