-- Run once against the existing SOOPI PostgreSQL database before starting the new API.
-- Safe to rerun: the version marker prevents resetting restaurants already reviewed.
BEGIN;
CREATE TABLE IF NOT EXISTS "ManagementSchemaVersions" (
    "Version" text PRIMARY KEY,
    "AppliedAt" timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
SELECT pg_advisory_xact_lock(2026101401);
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM "ManagementSchemaVersions" WHERE "Version" = 'restaurant-management-v1') THEN
        ALTER TABLE "Restaurants" ADD COLUMN IF NOT EXISTS "ApprovalStatus" varchar(20) NOT NULL DEFAULT 'Pending';
        ALTER TABLE "Restaurants" ADD COLUMN IF NOT EXISTS "IsLocked" boolean NOT NULL DEFAULT false;
        ALTER TABLE "Restaurants" ADD COLUMN IF NOT EXISTS "ReviewReason" text;
        ALTER TABLE "Restaurants" ADD COLUMN IF NOT EXISTS "ReviewedBy" uuid;
        ALTER TABLE "Restaurants" ADD COLUMN IF NOT EXISTS "ReviewedAt" timestamptz;
        ALTER TABLE "MenuItems" ADD COLUMN IF NOT EXISTS "IsDeleted" boolean NOT NULL DEFAULT false;
        ALTER TABLE "Restaurants" ALTER COLUMN "IsAcceptingOrders" SET DEFAULT false;
        UPDATE "Restaurants" SET "ApprovalStatus" = 'Pending', "IsAcceptingOrders" = false;
        INSERT INTO "ManagementSchemaVersions" ("Version") VALUES ('restaurant-management-v1');
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS "IX_Restaurants_OwnerId_ApprovalStatus" ON "Restaurants" ("OwnerId", "ApprovalStatus");
CREATE TABLE IF NOT EXISTS "ManagementAudits" (
    "Id" uuid PRIMARY KEY,
    "ActorId" uuid NOT NULL,
    "TargetId" uuid NOT NULL,
    "TargetType" text NOT NULL,
    "Action" text NOT NULL,
    "Reason" text,
    "CreatedAt" timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS "IX_ManagementAudits_TargetId_CreatedAt" ON "ManagementAudits" ("TargetId", "CreatedAt");
COMMIT;
