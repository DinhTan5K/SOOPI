# SOOPI FOOD API

Backend ASP.NET Core Web API (.NET 8) for the existing Flutter app. The API is organized into `Models` (domain entities), `DataAccess/Dao` (EF persistence), `DataAccess/Repositories` (queries), `Services` (business rules), `Contracts` (request DTOs), and `Controllers` (HTTP endpoints). PostgreSQL is the relational database; entity keys are UUIDs.

Restaurant ownership, approval, category/menu management and administrator APIs are documented in [backend/RESTAURANT_API.md](backend/RESTAURANT_API.md). Apply `database/restaurant_management_upgrade.sql` to an existing database before starting this version; existing restaurants require review again.

## Start locally

1. Create a PostgreSQL database named `soopifood` (for example, in pgAdmin), then run `database/soopifood.sql` against it.
2. Configure `ConnectionStrings__SoopiFood` using your PostgreSQL credentials, or use the ignored `backend/appsettings.Local.json` file.
3. From the `SOOPI` folder, run `dotnet restore SoopiFood.sln` and `dotnet run --project backend/Soopi.Backend.csproj`. Swagger is available in Development mode at `/swagger`.

Restaurant management and admin routes require Firebase JWTs and server-side ownership/Admin checks; ownership does not require changing a Customer's role. Legacy restaurant writes and account-lock routes are also protected. Older customer/order endpoints still use IDs in their URLs and are outside this restaurant API change. Payment providers are represented by `Payments`; provider callbacks and production payment signing are not configured.

## UC coverage and main tables

| UC | API area | Tables |
| --- | --- | --- |
| UC02 Profile and addresses | `api/users` | Users, UserAddresses |
| UC03 Restaurant search and menu | `api/restaurants` | Restaurants, MenuCategories, MenuItems, OpeningHours, Reviews |
| UC04 Cart | `api/users/{id}/cart` | Carts, CartItems |
| UC05 Checkout, coupon, payment choice | `api/users/{id}/orders` | Orders, OrderItems, Coupons, Payments |
| UC06 Order tracking/history | `api/users/{id}/orders` | Orders, OrderStatusHistory, DeliveryLocations |
| UC07 Order history | `api/users/{id}/orders` | Orders, OrderItems |
| UC08 Ratings and comments | `api/users/{id}/orders/{orderId}/review` | Reviews |
| UC09 Favorites | `api/restaurants/favorites` | Favorites |
| UC10 Restaurant profile and operating state | `api/restaurants/{id}/owner/{ownerId}` | Restaurants, OpeningHours |
| UC11 Menu management | `api/restaurants/owner/{ownerId}/menu` | MenuCategories, MenuItems |
| UC20 Lock/unlock accounts | `api/users/{id}/lock?locked=true|false` | Users.IsLocked |

The screenshots provided show UC02–UC11 and UC20 only; earlier/later use cases are not inferred. `database/soopifood.sql` contains PostgreSQL DDL, UUID keys, foreign keys, indexes, and value checks. Order lines keep a name/price snapshot so later menu edits do not rewrite past orders.
