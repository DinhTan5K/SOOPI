# SOOPI FOOD API

Backend ASP.NET Core Web API (.NET 9) for the existing Flutter app. The API is organized into `Models` (domain entities), `DataAccess/Dao` (EF persistence), `DataAccess/Repositories` (queries), `Services` (business rules), `Contracts` (request DTOs), and `Controllers` (HTTP endpoints). SQL Server is the relational database.

## Start locally

1. Run `database/soopifood.sql` in SQL Server Management Studio. The default API connection uses SQL Server LocalDB; edit `SoopiFoodBE/appsettings.json` for another SQL Server.
2. From the `SOOPI` folder, run `dotnet restore SoopiFood.sln` and `dotnet run --project SoopiFoodBE`. Swagger is available in Development mode at `/swagger`.

The current endpoints accept user/owner IDs in the route to make integration straightforward. Before exposing the API, validate those IDs against Firebase-authenticated claims and enforce Customer/Owner/Admin/Shipper role policies. Payment providers are represented by `Payments`; provider callbacks and production payment signing are not configured.

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

The screenshots provided show UC02–UC11 and UC20 only; earlier/later use cases are not inferred. `database/soopifood.sql` contains the SQL Server DDL, foreign keys, uniqueness rules, indexes, and value checks. Order lines keep a name/price snapshot so later menu edits do not rewrite past orders.
