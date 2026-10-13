-- PostgreSQL schema for SOOPI FOOD.
-- Connect to the soopifood database before running this script.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid varchar(128) NOT NULL,
    full_name varchar(150) NOT NULL,
    email varchar(150) NOT NULL,
    phone_number varchar(20),
    avatar_url varchar(500),
    gender varchar(20) DEFAULT 'Nam',
    date_of_birth timestamptz,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz,
    role varchar(20) NOT NULL DEFAULT 'Customer'
        CHECK (role IN ('Customer', 'Owner', 'Shipper', 'Admin')),
    is_locked boolean NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_users_firebase_uid"
    ON users (firebase_uid);
CREATE INDEX IF NOT EXISTS "IX_users_email"
    ON users (email);

CREATE TABLE IF NOT EXISTS user_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid varchar(128) NOT NULL,
    user_id uuid,
    label varchar(50) NOT NULL DEFAULT 'Nhà riêng',
    recipient_name varchar(100) NOT NULL,
    phone_number varchar(20) NOT NULL,
    full_address varchar(500) NOT NULL,
    note varchar(255),
    is_default boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz,
    CONSTRAINT "FK_user_addresses_users_user_id"
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "IX_user_addresses_firebase_uid"
    ON user_addresses (firebase_uid);
CREATE INDEX IF NOT EXISTS "IX_user_addresses_user_id"
    ON user_addresses (user_id);

CREATE TABLE IF NOT EXISTS "Restaurants" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "OwnerId" uuid REFERENCES users(id) ON DELETE SET NULL,
    "Name" varchar(200) NOT NULL,
    "Description" varchar(1000) NOT NULL DEFAULT '',
    "Phone" varchar(30) NOT NULL DEFAULT '',
    "Address" varchar(500) NOT NULL,
    "City" varchar(100) NOT NULL,
    "ImageUrl" varchar(1000),
    "Latitude" numeric(10,7),
    "Longitude" numeric(10,7),
    "AverageRating" numeric(3,2) NOT NULL DEFAULT 0
        CHECK ("AverageRating" BETWEEN 0 AND 5),
    "ReviewCount" integer NOT NULL DEFAULT 0,
    "TotalOrders" integer NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "IsAcceptingOrders" boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS "OpeningHours" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "RestaurantId" uuid NOT NULL REFERENCES "Restaurants"("Id") ON DELETE CASCADE,
    "DayOfWeek" smallint NOT NULL CHECK ("DayOfWeek" BETWEEN 0 AND 6),
    "OpensAt" time NOT NULL,
    "ClosesAt" time NOT NULL,
    "IsClosed" boolean NOT NULL DEFAULT false,
    CONSTRAINT "UQ_OpeningHours_Restaurant_Day"
        UNIQUE ("RestaurantId", "DayOfWeek")
);

CREATE TABLE IF NOT EXISTS "MenuCategories" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "RestaurantId" uuid NOT NULL REFERENCES "Restaurants"("Id") ON DELETE CASCADE,
    "Name" varchar(100) NOT NULL,
    "SortOrder" integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS "MenuItems" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "CategoryId" uuid NOT NULL REFERENCES "MenuCategories"("Id") ON DELETE CASCADE,
    "Name" varchar(200) NOT NULL,
    "Description" varchar(1000) NOT NULL DEFAULT '',
    "Price" numeric(12,2) NOT NULL CHECK ("Price" >= 0),
    "OriginalPrice" numeric(12,2),
    "DiscountPercent" integer DEFAULT 0,
    "ImageUrl" varchar(1000),
    "SoldCount" integer NOT NULL DEFAULT 0,
    "LikesCount" integer NOT NULL DEFAULT 0,
    "IsAvailable" boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS "Carts" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "UserId" uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    "RestaurantId" uuid REFERENCES "Restaurants"("Id"),
    "UpdatedAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "CartItems" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "CartId" uuid NOT NULL REFERENCES "Carts"("Id") ON DELETE CASCADE,
    "MenuItemId" uuid NOT NULL REFERENCES "MenuItems"("Id"),
    "Quantity" integer NOT NULL CHECK ("Quantity" > 0),
    "Note" varchar(500) NOT NULL DEFAULT '',
    CONSTRAINT "UQ_CartItems_Cart_Menu" UNIQUE ("CartId", "MenuItemId")
);

CREATE TABLE IF NOT EXISTS "Coupons" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "Code" varchar(50) NOT NULL UNIQUE,
    "DiscountType" varchar(20) NOT NULL CHECK ("DiscountType" IN ('Percent', 'Fixed')),
    "DiscountValue" numeric(12,2) NOT NULL CHECK ("DiscountValue" > 0),
    "MinOrderAmount" numeric(12,2) NOT NULL DEFAULT 0,
    "MaxDiscount" numeric(12,2),
    "StartsAt" timestamptz,
    "EndsAt" timestamptz,
    "UsageLimit" integer,
    "UsedCount" integer NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS "Orders" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "OrderCode" varchar(40) NOT NULL UNIQUE,
    "CustomerId" uuid NOT NULL REFERENCES users(id),
    "RestaurantId" uuid NOT NULL REFERENCES "Restaurants"("Id"),
    "ShipperId" uuid REFERENCES users(id),
    "AddressId" uuid REFERENCES user_addresses(id) ON DELETE SET NULL,
    "DeliveryAddress" varchar(1000) NOT NULL,
    "Subtotal" numeric(12,2) NOT NULL,
    "DiscountAmount" numeric(12,2) NOT NULL DEFAULT 0,
    "DeliveryFee" numeric(12,2) NOT NULL DEFAULT 0,
    "TotalAmount" numeric(12,2) NOT NULL,
    "Status" varchar(30) NOT NULL DEFAULT 'Pending'
        CHECK ("Status" IN ('Pending', 'Accepted', 'Preparing', 'ReadyForPickup', 'PickedUp', 'Delivering', 'Delivered', 'Cancelled')),
    "PaymentMethod" varchar(30) NOT NULL
        CHECK ("PaymentMethod" IN ('Cash', 'Card', 'EWallet')),
    "PaymentStatus" varchar(30) NOT NULL DEFAULT 'Unpaid',
    "CouponCode" varchar(50),
    "Note" varchar(500) NOT NULL DEFAULT '',
    "CreatedAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "UpdatedAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "IX_Orders_Customer_Created"
    ON "Orders" ("CustomerId", "CreatedAt" DESC);

CREATE TABLE IF NOT EXISTS "OrderItems" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "OrderId" uuid NOT NULL REFERENCES "Orders"("Id") ON DELETE CASCADE,
    "MenuItemId" uuid REFERENCES "MenuItems"("Id") ON DELETE SET NULL,
    "ItemName" varchar(200) NOT NULL,
    "UnitPrice" numeric(12,2) NOT NULL,
    "Quantity" integer NOT NULL CHECK ("Quantity" > 0),
    "Note" varchar(500) NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS "OrderStatusHistory" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "OrderId" uuid NOT NULL REFERENCES "Orders"("Id") ON DELETE CASCADE,
    "Status" varchar(30) NOT NULL,
    "ChangedAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "Note" varchar(500)
);

CREATE TABLE IF NOT EXISTS "Payments" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "OrderId" uuid NOT NULL REFERENCES "Orders"("Id"),
    "Method" varchar(30) NOT NULL,
    "Amount" numeric(12,2) NOT NULL,
    "Status" varchar(30) NOT NULL,
    "ProviderReference" varchar(200),
    "CreatedAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Reviews" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "OrderId" uuid NOT NULL UNIQUE REFERENCES "Orders"("Id"),
    "CustomerId" uuid NOT NULL REFERENCES users(id),
    "RestaurantId" uuid NOT NULL REFERENCES "Restaurants"("Id"),
    "ShipperId" uuid REFERENCES users(id),
    "RestaurantRating" smallint NOT NULL CHECK ("RestaurantRating" BETWEEN 1 AND 5),
    "ShipperRating" smallint CHECK ("ShipperRating" BETWEEN 1 AND 5),
    "Comment" varchar(2000) NOT NULL DEFAULT '',
    "CreatedAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Favorites" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "UserId" uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    "RestaurantId" uuid NOT NULL REFERENCES "Restaurants"("Id") ON DELETE CASCADE,
    "CreatedAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "UQ_Favorites_User_Restaurant" UNIQUE ("UserId", "RestaurantId")
);

CREATE TABLE IF NOT EXISTS "DeliveryLocations" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "OrderId" uuid NOT NULL REFERENCES "Orders"("Id") ON DELETE CASCADE,
    "ShipperId" uuid NOT NULL REFERENCES users(id),
    "Latitude" numeric(10,7) NOT NULL,
    "Longitude" numeric(10,7) NOT NULL,
    "RecordedAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "IX_DeliveryLocations_Order_Time"
    ON "DeliveryLocations" ("OrderId", "RecordedAt" DESC);
