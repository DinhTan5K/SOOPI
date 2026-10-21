BEGIN;
ALTER TABLE "Coupons" ADD COLUMN IF NOT EXISTS "RestaurantId" uuid REFERENCES "Restaurants"("Id") ON DELETE RESTRICT;
ALTER TABLE "Coupons" ADD COLUMN IF NOT EXISTS "MenuItemId" uuid REFERENCES "MenuItems"("Id") ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS "IX_Coupons_RestaurantId" ON "Coupons"("RestaurantId");
CREATE INDEX IF NOT EXISTS "IX_Coupons_MenuItemId" ON "Coupons"("MenuItemId");
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'CK_Coupons_Scope' AND conrelid = '"Coupons"'::regclass) THEN
        ALTER TABLE "Coupons" ADD CONSTRAINT "CK_Coupons_Scope" CHECK ("MenuItemId" IS NULL OR "RestaurantId" IS NOT NULL);
    END IF;
END $$;
COMMIT;
