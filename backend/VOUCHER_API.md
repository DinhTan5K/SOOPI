# Voucher API

Apply `database/voucher_management_upgrade.sql` after the restaurant management upgrade on an existing PostgreSQL database. New installations use `database/soopifood.sql`. `EnsureCreated()` does not upgrade existing tables. The upgrade is repeatable and preserves legacy global coupons.

## Merchant

All routes require `Authorization: Bearer <Firebase ID token>`. The authenticated account must own the restaurant; locked restaurants cannot be managed. Base: `/api/merchant/restaurants/{restaurantId}/vouchers`.

| Method | Path | Result |
| --- | --- | --- |
| GET | base | Array of all vouchers owned by this restaurant |
| POST | base | 201 with voucher and Location header |
| GET | `/{voucherId}` | Voucher details |
| PATCH | `/{voucherId}/status` | Updated voucher; body `{"isActive":false}` |

Create example (omit `menuItemId` or set null for the whole restaurant):

```json
{
  "code": "COM20",
  "menuItemId": null,
  "discountType": "Percent",
  "discountValue": 20,
  "minOrderAmount": 50000,
  "maxDiscount": 30000,
  "startsAt": "2026-10-21T00:00:00+07:00",
  "endsAt": "2026-11-21T23:59:00+07:00",
  "usageLimit": 100,
  "isActive": true
}
```

Codes contain 1–50 ASCII letters, digits, `_` or `-`; stored uppercase, globally unique ignoring case. `discountType` is `Percent` (>0 through 100) or `Fixed` (>0 VND). Monetary fields accept at most two decimal places. Minimum defaults to 0; maximum discount and usage limit are optional positive values. Optional start/end accept ISO 8601 offsets, are stored UTC, and end must follow start when both are supplied. Menu item must belong to the restaurant. Content editing/deletion is not provided; disable old vouchers and create new ones.

Response fields: `id`, `code`, `restaurantId`, nullable `menuItemId`, `scope` (`Restaurant`/`MenuItem`), all creation fields, `usedCount`, `status` (`Inactive`, `Expired`, `Exhausted`, `Scheduled`, `Active`). The list includes every status. Dates are UTC; clients display local time.

Errors: 400 invalid input, 401 missing/invalid authentication, 403 locked/unauthorized account, 404 restaurant/voucher unavailable to this owner, 409 duplicate code or concurrent change. Errors use ProblemDetails (`title`); preview may return `{ "error": "..." }`. On 409 reload before retrying. Do not automatically retry checkout: a new checkout request can create a separate order.

## Customer integration (no customer UI included)

`GET /api/restaurants/{restaurantId}/vouchers` is public and returns the same array shape, filtered to active, started, unexpired vouchers with remaining uses. Deleted target menu items are excluded. Restaurant must be approved, active and unlocked. A listed voucher may still be ineligible for a particular cart.

`POST /api/users/{userId}/cart/vouchers/preview` requires a Firebase bearer token matching `userId`, and body:

```json
{ "couponCode": "COM20" }
```

The cart and menu prices come from the server. Example response:

```json
{
  "couponCode": "COM20",
  "subtotal": 100000,
  "eligibleAmount": 100000,
  "discountAmount": 20000,
  "deliveryFee": 15000,
  "totalAmount": 95000
}
```

Preview never consumes usage or reserves a voucher. Invalid, expired, exhausted, wrong-restaurant/missing-item codes and carts below the minimum return 400. Empty carts return 400; another user's cart returns 403.

Submit `couponCode` in the existing checkout body (`POST /api/users/{userId}/orders`) or direct order body (`POST /api/users/{userId}/orders/direct`). Both recalculate the discount and reject invalid codes. The direct order route takes explicit menu IDs/quantities and uses server prices, requiring all items to belong to its restaurant. Its existing delivery fee is 16000; cart checkout/preview use 15000. For direct ordering, the consuming UI can use list results to display vouchers; this release's preview uses the persisted cart only.

One code per order. Restaurant vouchers discount all food; item vouchers discount the sum of all quantities of that item. Minimum order checks the entire food subtotal. Fixed discounts apply once, percentages apply to the eligible sum, then maximum discount and eligible subtotal cap the result. Delivery fee is never discounted. Calculated discount rounds to two decimals. Existing menu pricing is preserved; this feature does not change `DiscountPercent` pricing behavior.

PostgreSQL `xmin` concurrency checking ensures that consuming a voucher and saving the order/payment/cart changes happen in the same EF save transaction. Two requests based on the same coupon version cannot both consume it; the losing save rolls back and returns 409. Preview is advisory; handle rejection at checkout even after successful preview. Existing global coupons remain usable in checkout but never appear in merchant/customer restaurant voucher lists.

## Verification on PostgreSQL

Run `dotnet test backend.tests/Soopi.Backend.Tests.csproj`. Unit/API tests run with an isolated InMemory provider. Set `SOOPI_TEST_CONNECTION` to a PostgreSQL connection with CREATE DATABASE permission to enable the PostgreSQL integration test; it creates and drops its own uniquely named `soopi_voucher_test_*` database, applies the upgrade twice over a legacy coupon, then verifies optimistic concurrency and losing-order rollback. Without this variable, that integration test is explicitly skipped.

Apply the upgrade twice and verify pre-existing coupons remain unchanged. With two owner accounts, verify owner B cannot access owner A's voucher routes and cannot create a voucher targeting A's menu. Create restaurant and item vouchers; verify preview/checkout agree, preview does not increase `UsedCount`, and unrelated restaurants/items are rejected. For a voucher with one remaining use, submit two independent checkouts concurrently: only one order may persist, the other must return 400 or 409, and usage must remain at its limit. Repeat with direct checkout and verify invalid codes fail rather than silently placing an undiscounted order.
