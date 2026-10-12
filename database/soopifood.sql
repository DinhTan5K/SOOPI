/* SQL Server schema for SOOPI FOOD. Money is stored as VND decimal(12,2). */
IF DB_ID(N'SoopiFood') IS NULL CREATE DATABASE SoopiFood;
GO
USE SoopiFood;
GO
CREATE TABLE dbo.Users (
 Id int IDENTITY PRIMARY KEY, FirebaseUid nvarchar(128) NULL UNIQUE, Email nvarchar(255) NOT NULL UNIQUE,
 FullName nvarchar(150) NOT NULL, AvatarUrl nvarchar(1000) NULL, Phone nvarchar(30) NOT NULL DEFAULT N'',
 Role nvarchar(20) NOT NULL DEFAULT N'Customer' CHECK (Role IN (N'Customer',N'Owner',N'Shipper',N'Admin')),
 IsLocked bit NOT NULL DEFAULT 0, CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE TABLE dbo.UserAddresses (
 Id int IDENTITY PRIMARY KEY, UserId int NOT NULL REFERENCES dbo.Users(Id) ON DELETE CASCADE,
 Label nvarchar(50) NOT NULL, RecipientName nvarchar(150) NOT NULL, Phone nvarchar(30) NOT NULL,
 Line nvarchar(300) NOT NULL, Ward nvarchar(100) NOT NULL, District nvarchar(100) NOT NULL, City nvarchar(100) NOT NULL,
 Latitude decimal(10,7) NULL, Longitude decimal(10,7) NULL, IsDefault bit NOT NULL DEFAULT 0);
CREATE TABLE dbo.Restaurants (
 Id int IDENTITY PRIMARY KEY, OwnerId int NULL REFERENCES dbo.Users(Id), Name nvarchar(200) NOT NULL,
 Description nvarchar(1000) NOT NULL DEFAULT N'', Phone nvarchar(30) NOT NULL DEFAULT N'', Address nvarchar(500) NOT NULL,
 City nvarchar(100) NOT NULL, ImageUrl nvarchar(1000) NULL, Latitude decimal(10,7) NULL, Longitude decimal(10,7) NULL,
 AverageRating decimal(3,2) NOT NULL DEFAULT 0 CHECK (AverageRating BETWEEN 0 AND 5),
 IsActive bit NOT NULL DEFAULT 1, IsAcceptingOrders bit NOT NULL DEFAULT 1);
CREATE TABLE dbo.OpeningHours (
 Id int IDENTITY PRIMARY KEY, RestaurantId int NOT NULL REFERENCES dbo.Restaurants(Id) ON DELETE CASCADE,
 DayOfWeek tinyint NOT NULL CHECK (DayOfWeek BETWEEN 0 AND 6), OpensAt time NOT NULL, ClosesAt time NOT NULL,
 IsClosed bit NOT NULL DEFAULT 0, CONSTRAINT UQ_OpeningHours_Restaurant_Day UNIQUE(RestaurantId,DayOfWeek));
CREATE TABLE dbo.MenuCategories (
 Id int IDENTITY PRIMARY KEY, RestaurantId int NOT NULL REFERENCES dbo.Restaurants(Id) ON DELETE CASCADE,
 Name nvarchar(100) NOT NULL, SortOrder int NOT NULL DEFAULT 0);
CREATE TABLE dbo.MenuItems (
 Id int IDENTITY PRIMARY KEY, CategoryId int NOT NULL REFERENCES dbo.MenuCategories(Id) ON DELETE CASCADE,
 Name nvarchar(200) NOT NULL, Description nvarchar(1000) NOT NULL DEFAULT N'', Price decimal(12,2) NOT NULL CHECK(Price>=0),
 ImageUrl nvarchar(1000) NULL, IsAvailable bit NOT NULL DEFAULT 1);
CREATE TABLE dbo.Carts (
 Id int IDENTITY PRIMARY KEY, UserId int NOT NULL UNIQUE REFERENCES dbo.Users(Id) ON DELETE CASCADE,
 RestaurantId int NULL REFERENCES dbo.Restaurants(Id), UpdatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE TABLE dbo.CartItems (
 Id int IDENTITY PRIMARY KEY, CartId int NOT NULL REFERENCES dbo.Carts(Id) ON DELETE CASCADE,
 MenuItemId int NOT NULL REFERENCES dbo.MenuItems(Id), Quantity int NOT NULL CHECK(Quantity>0), Note nvarchar(500) NOT NULL DEFAULT N'',
 CONSTRAINT UQ_CartItems_Cart_Menu UNIQUE(CartId,MenuItemId));
CREATE TABLE dbo.Coupons (
 Id int IDENTITY PRIMARY KEY, Code nvarchar(50) NOT NULL UNIQUE, DiscountType nvarchar(20) NOT NULL CHECK(DiscountType IN(N'Percent',N'Fixed')),
 DiscountValue decimal(12,2) NOT NULL CHECK(DiscountValue>0), MinOrderAmount decimal(12,2) NOT NULL DEFAULT 0,
 MaxDiscount decimal(12,2) NULL, StartsAt datetime2 NULL, EndsAt datetime2 NULL, UsageLimit int NULL,
 UsedCount int NOT NULL DEFAULT 0, IsActive bit NOT NULL DEFAULT 1);
CREATE TABLE dbo.Orders (
 Id int IDENTITY PRIMARY KEY, OrderCode nvarchar(40) NOT NULL UNIQUE,
 CustomerId int NOT NULL REFERENCES dbo.Users(Id), RestaurantId int NOT NULL REFERENCES dbo.Restaurants(Id),
 ShipperId int NULL REFERENCES dbo.Users(Id), AddressId int NULL REFERENCES dbo.UserAddresses(Id) ON DELETE SET NULL,
 DeliveryAddress nvarchar(1000) NOT NULL, Subtotal decimal(12,2) NOT NULL, DiscountAmount decimal(12,2) NOT NULL DEFAULT 0,
 DeliveryFee decimal(12,2) NOT NULL DEFAULT 0, TotalAmount decimal(12,2) NOT NULL,
 Status nvarchar(30) NOT NULL DEFAULT N'Pending' CHECK(Status IN(N'Pending',N'Accepted',N'Preparing',N'ReadyForPickup',N'PickedUp',N'Delivering',N'Delivered',N'Cancelled')),
 PaymentMethod nvarchar(30) NOT NULL CHECK(PaymentMethod IN(N'Cash',N'Card',N'EWallet')),
 PaymentStatus nvarchar(30) NOT NULL DEFAULT N'Unpaid', CouponCode nvarchar(50) NULL, Note nvarchar(500) NOT NULL DEFAULT N'',
 CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), UpdatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE INDEX IX_Orders_Customer_Created ON dbo.Orders(CustomerId,CreatedAt DESC);
CREATE TABLE dbo.OrderItems (
 Id int IDENTITY PRIMARY KEY, OrderId int NOT NULL REFERENCES dbo.Orders(Id) ON DELETE CASCADE,
 MenuItemId int NULL REFERENCES dbo.MenuItems(Id) ON DELETE SET NULL, ItemName nvarchar(200) NOT NULL,
 UnitPrice decimal(12,2) NOT NULL, Quantity int NOT NULL CHECK(Quantity>0), Note nvarchar(500) NOT NULL DEFAULT N'');
CREATE TABLE dbo.OrderStatusHistory (
 Id int IDENTITY PRIMARY KEY, OrderId int NOT NULL REFERENCES dbo.Orders(Id) ON DELETE CASCADE,
 Status nvarchar(30) NOT NULL, ChangedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), Note nvarchar(500) NULL);
CREATE TABLE dbo.Payments (
 Id int IDENTITY PRIMARY KEY, OrderId int NOT NULL REFERENCES dbo.Orders(Id), Method nvarchar(30) NOT NULL,
 Amount decimal(12,2) NOT NULL, Status nvarchar(30) NOT NULL, ProviderReference nvarchar(200) NULL,
 CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE TABLE dbo.Reviews (
 Id int IDENTITY PRIMARY KEY, OrderId int NOT NULL UNIQUE REFERENCES dbo.Orders(Id), CustomerId int NOT NULL REFERENCES dbo.Users(Id),
 RestaurantId int NOT NULL REFERENCES dbo.Restaurants(Id), ShipperId int NULL REFERENCES dbo.Users(Id),
 RestaurantRating tinyint NOT NULL CHECK(RestaurantRating BETWEEN 1 AND 5), ShipperRating tinyint NULL CHECK(ShipperRating BETWEEN 1 AND 5),
 Comment nvarchar(2000) NOT NULL DEFAULT N'', CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE TABLE dbo.Favorites (
 Id int IDENTITY PRIMARY KEY, UserId int NOT NULL REFERENCES dbo.Users(Id) ON DELETE CASCADE,
 RestaurantId int NOT NULL REFERENCES dbo.Restaurants(Id) ON DELETE CASCADE, CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_Favorites_User_Restaurant UNIQUE(UserId,RestaurantId));
CREATE TABLE dbo.DeliveryLocations (
 Id bigint IDENTITY PRIMARY KEY, OrderId int NOT NULL REFERENCES dbo.Orders(Id) ON DELETE CASCADE,
 ShipperId int NOT NULL REFERENCES dbo.Users(Id), Latitude decimal(10,7) NOT NULL, Longitude decimal(10,7) NOT NULL,
 RecordedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE INDEX IX_DeliveryLocations_Order_Time ON dbo.DeliveryLocations(OrderId,RecordedAt DESC);
