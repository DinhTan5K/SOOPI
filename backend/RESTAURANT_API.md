# Restaurant and administrator APIs

The existing Firebase account owns restaurants through `Restaurant.OwnerId`. One account can own multiple restaurants without changing its `Customer` role. There is no separate restaurant password, merchant Firebase project or automatic promotion to `Owner`/`Admin`.

## Start and initialize PostgreSQL

Requirements: .NET 8, PostgreSQL 16, the Firebase project used by the app, SMTP for existing email OTP, and Cloudinary for images.

- Fresh database: run `database/soopifood.sql`, then `database/restaurant_management_upgrade.sql`.
- Existing database: run **only** `database/restaurant_management_upgrade.sql` before starting this version. It marks every existing restaurant `Pending` and disables accepting orders, without deleting accounts, menu or history. A version marker makes subsequent runs safe and preserves later approvals.
- `EnsureCreated` does not upgrade existing tables. Apply the SQL explicitly; do not reset the database.

The current Docker container is `soopi-postgres`, database/user `soopi`, exposed on `127.0.0.1:5432`.

Configure `ConnectionStrings__SoopiFood` with that container's credentials. The ignored `backend/appsettings.Local.json` is also loaded; environment variables override it. Set `Firebase__ProjectId`, `Cloudinary__CloudName`, `Cloudinary__ApiKey`, and `Cloudinary__ApiSecret` through environment variables or .NET user secrets. Existing email OTP uses `EmailSettings__SmtpHost`, `EmailSettings__SmtpPort`, `EmailSettings__SenderEmail`, `EmailSettings__SenderPassword`, `EmailSettings__SenderName` and `EmailSettings__EnableSsl`. Do not commit credentials.

```powershell
dotnet restore SoopiFood.sln
dotnet run --project backend/Soopi.Backend.csproj -- --urls http://localhost:5000
```

Set `ASPNETCORE_ENVIRONMENT=Development` to open `http://localhost:5000/swagger`. Swagger includes JSON request examples for the new endpoints. Replace the sample category UUID with an ID returned by your restaurant.

## Account registration and authentication

Register/sign in using the existing Firebase email/password flow. The existing `POST /api/auth/send-registration-otp` and `POST /api/auth/verify-registration-otp` support the app's registration flow; restaurant registration itself is creating a restaurant after signing in.

For API-only testing, create an account using Firebase Authentication, then obtain an **ID token** with the Firebase SDK or Identity Toolkit `accounts:signInWithPassword` endpoint using the project's Web API key. A Firebase custom token, API key or refresh token is not an ID token.

Send `Authorization: Bearer <Firebase ID token>` to management APIs. In Swagger's Authorize dialog, paste only the token; Swagger adds `Bearer`. ID tokens expire; sign in/refresh as needed.

`GET /api/merchant/me` synchronizes a missing database profile by the verified Firebase UID and returns `{ id, email, fullName, phone, avatarUrl, hasRestaurants }`. Existing profile creation uses authenticated claims only: `X-Dev-Uid` and `X-Firebase-Uid` headers cannot authenticate a caller or link an existing account by email.

## Restaurant workflow

1. Call `GET /api/merchant/me` with a Firebase ID token.
2. Call `POST /api/merchant/restaurants` with:

```json
{
  "name": "Bếp Soopi",
  "description": "Cơm và đồ uống",
  "phone": "0901234567",
  "address": "12 Nguyễn Văn Bảo",
  "city": "Hồ Chí Minh",
  "imageUrl": null,
  "latitude": 10.822,
  "longitude": 106.688
}
```

Response `201` includes its `id`, server-assigned `ownerId`, `approvalStatus: Pending`, `isAcceptingOrders: false`, three default categories and their UUIDs. Supplying `ownerId`, role or approval fields cannot change the server assignment.

3. Prepare categories, menu and hours while waiting for approval.
4. An administrator approves or rejects the restaurant. Rejection includes a reason; edit and call `POST /api/merchant/restaurants/{id}/resubmit` to return to Pending.
5. After approval, explicitly enable operation with `PATCH /api/merchant/restaurants/{id}/operation` and `{ "isActive": true, "isAcceptingOrders": true }`. Approval alone does not start accepting orders.

Updating identity information on an approved restaurant through `PUT /api/merchant/restaurants/{id}` returns it to Pending and disables accepting orders. Menu and hours changes do not trigger review. Approval history is retained; `reviewReason` represents the last review and is not an administrator lock reason.

Owners may read details/status of their locked restaurants but cannot modify them. Admin locks are separate from approval and operational settings. Unlocking does not approve a restaurant or enable accepting orders automatically.

### Merchant endpoints

All restaurant IDs, category IDs and item IDs must belong to the authenticated account and the restaurant in the URL.

| Method | Path below `/api/merchant` | Purpose |
|---|---|---|
| GET | `/me` | Account profile and ownership flag |
| GET | `/restaurants?status=Pending&page=1&pageSize=20` | My restaurants |
| POST | `/restaurants` | Create and link a restaurant |
| GET / PUT | `/restaurants/{id}` | Read/update restaurant |
| POST | `/restaurants/{id}/resubmit` | Resubmit a rejected restaurant |
| PATCH | `/restaurants/{id}/operation` | Operational switches |
| PUT | `/restaurants/{id}/hours/{day}` | Hours, Sunday = 0 through Saturday = 6 |
| GET / POST | `/restaurants/{id}/categories` | List/create categories |
| PUT / DELETE | `/restaurants/{id}/categories/{categoryId}` | Update/delete empty category |
| GET / POST | `/restaurants/{id}/menu` | List/create menu items |
| GET / PUT / DELETE | `/restaurants/{id}/menu/{itemId}` | Read/update/archive item |
| PATCH | `/restaurants/{id}/menu/{itemId}/availability` | Set availability |
| POST | `/restaurants/{id}/images` | Multipart form file upload |

Menu request example:

```json
{
  "categoryId": "<category UUID returned by your restaurant>",
  "name": "Cơm gà",
  "description": "Cơm gà và rau",
  "price": 45000,
  "imageUrl": null,
  "isAvailable": true
}
```

Category request: `{ "name": "Món chính", "sortOrder": 0 }`. Availability: `{ "isAvailable": false }`. Hours: `{ "opensAt": "08:00:00", "closesAt": "22:00:00", "isClosed": false }`. Overnight hours are not supported in this version; on open days, opening time must precede closing time.

Deleting a menu item archives it and hides it from menu queries while preserving historical references. Categories containing any items, including archived ones, cannot be deleted. Images accept JPEG/PNG/WebP, matching MIME/signature, up to 5 MB, and return `{ "imageUrl": "https://..." }`; assign that URL to the restaurant/item in a separate save request. Cloudinary credentials remain server-side; a service failure returns `503`.

## Admin APIs and bootstrap

Create/sign in to the admin's Firebase account and call `/api/merchant/me` first. Then run this SQL using the real UID:

```sql
UPDATE users SET role = 'Admin'
WHERE firebase_uid = '<existing Firebase UID>';
```

Verify that exactly the intended row changed. There is no public API for granting Admin. Admin permissions are read from the database, not from a client-supplied role.

| Method | Path below `/api/admin` | Purpose |
|---|---|---|
| GET | `/restaurants?q=...&status=Pending&locked=false&page=1&pageSize=20` | Search/filter restaurants |
| GET | `/restaurants/{id}` | Restaurant, owner and review/lock history |
| POST | `/restaurants/{id}/approve` | Approve Pending restaurant, no body |
| POST | `/restaurants/{id}/reject` | Reject Pending with `{ "reason": "..." }` |
| PATCH | `/restaurants/{id}/lock` | `{ "locked": true, "reason": "..." }` |
| GET | `/users?q=...&role=Customer&locked=false&page=1&pageSize=20` | Search/filter accounts |
| GET | `/users/{id}` | Account, owned restaurants and lock history |
| PATCH | `/users/{id}/lock` | Lock/unlock account |

Locking requires a nonblank reason. Unlock with `{ "locked": false }`. Administrator accounts cannot be locked through these routes. Approval requires Pending, an existing unlocked owner and an unlocked restaurant. Restaurants with no OwnerId must first be assigned to a real account by a database administrator; there is no ownership-transfer endpoint in this version.

Locking an account blocks its management APIs and hides all its restaurants. Unlocking does not change restaurant approval or restaurant lock flags. Public search/detail/menu/favorites hide unapproved restaurants and restaurants with locked or absent owners; search also retains its existing operational filters.

Legacy restaurant write URLs now require Firebase authentication and validate `ownerId` against the signed-in account. The old `PUT /api/users/{id}/lock` is Admin-only; locking requires the new admin route with a reason, while legacy unlock is audited and protects Admin accounts.

## Errors and manual verification

List results use `{ items, total, page, pageSize }`, with page >= 1, pageSize 1–100 and default 20. Invalid input returns `400`, missing/invalid JWT `401`, locked/unauthorized access `403`, unknown or another owner's resources `404`, and invalid state/concurrent updates `409` in Problem Details format. Reload before retrying a conflicting write.

Use Swagger with two Firebase accounts and an administrator to verify creating multiple restaurants, owner isolation, approval/rejection/resubmission, category/menu management and account/restaurant locks. A real Firebase ID token and configured Cloudinary account are required for live image upload verification.

Flutter, order creation/processing, payments, push notifications and SignalR are outside this change.
