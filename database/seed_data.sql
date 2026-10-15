-- ============================================================================
-- SOOPI FOOD - SEED DATA SCRIPT
-- Database: PostgreSQL (soopi)
-- Ghi chú: Chèn dữ liệu mẫu cho TẤT CẢ các bảng trừ Orders, OrderItems, 
--          OrderStatusHistory, Payments, Reviews, DeliveryLocations 
--          để người dùng tự test các luồng đặt hàng trên ứng dụng.
-- ============================================================================

-- Kích hoạt extension pgcrypto nếu chưa có
CREATE EXTENSION IF NOT EXISTS pgcrypto;

BEGIN;

-- ============================================================================
-- 1. BẢNG USERS (Người dùng hệ thống: Admin, Owner, Shipper, Customer)
-- ============================================================================
INSERT INTO users (id, firebase_uid, full_name, email, phone_number, avatar_url, gender, date_of_birth, created_at, role, is_locked)
VALUES
    -- Chủ quán (Owners)
    ('11111111-0000-0000-0000-000000000001', 'owner_burger_01', 'Nguyễn Hoàng Long', 'owner.burger@soopi.vn', '0912345601', 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400', 'Nam', '1988-05-12', NOW(), 'Owner', false),
    ('11111111-0000-0000-0000-000000000002', 'owner_pizza_01', 'Trần Minh Quân', 'owner.pizza@soopi.vn', '0912345602', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400', 'Nam', '1985-09-20', NOW(), 'Owner', false),
    ('11111111-0000-0000-0000-000000000003', 'owner_sushi_01', 'Lê Thanh Thảo', 'owner.sushi@soopi.vn', '0912345603', 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400', 'Nữ', '1992-03-15', NOW(), 'Owner', false),
    ('11111111-0000-0000-0000-000000000004', 'owner_phuclong_01', 'Phạm Minh Trí', 'owner.phuclong@soopi.vn', '0912345604', 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400', 'Nam', '1990-11-28', NOW(), 'Owner', false),
    ('11111111-0000-0000-0000-000000000005', 'owner_comtam_01', 'Đặng Tuấn Kiệt', 'owner.comtam@soopi.vn', '0912345605', 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=400', 'Nam', '1982-01-08', NOW(), 'Owner', false),
    ('11111111-0000-0000-0000-000000000006', 'owner_healthy_01', 'Vũ Hải Yến', 'owner.healthy@soopi.vn', '0912345606', 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400', 'Nữ', '1995-07-22', NOW(), 'Owner', false),

    -- Tài xế giao hàng (Shippers)
    ('22222222-0000-0000-0000-000000000001', 'shipper_nam_01', 'Trần Văn Nam', 'shipper.nam@soopi.vn', '0901234567', 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=400', 'Nam', '1996-04-10', NOW(), 'Shipper', false),
    ('22222222-0000-0000-0000-000000000002', 'shipper_tuan_02', 'Lê Quốc Tuấn', 'shipper.tuan@soopi.vn', '0902345678', 'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=400', 'Nam', '1998-08-19', NOW(), 'Shipper', false),
    ('22222222-0000-0000-0000-000000000003', 'shipper_dat_03', 'Nguyễn Hữu Đạt', 'shipper.dat@soopi.vn', '0903456789', 'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=400', 'Nam', '1997-12-05', NOW(), 'Shipper', false),

    -- Khách hàng mẫu (Customer)
    ('33333333-0000-0000-0000-000000000001', 'customer_sample_01', 'Nguyễn Thu Trang', 'customer.trang@soopi.vn', '0988776655', 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=400', 'Nữ', '2000-10-10', NOW(), 'Customer', false),
    ('33333333-0000-0000-0000-000000000002', 'customer_sample_02', 'Hoàng Văn Bình', 'customer.binh@soopi.vn', '0988112233', 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400', 'Nam', '1998-04-12', NOW(), 'Customer', false),
    ('33333333-0000-0000-0000-000000000003', 'customer_sample_03', 'Lê Thị Mai', 'customer.mai@soopi.vn', '0977665544', 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400', 'Nữ', '2001-08-25', NOW(), 'Customer', false)
ON CONFLICT (firebase_uid) DO UPDATE
SET full_name = EXCLUDED.full_name,
    email = EXCLUDED.email,
    role = EXCLUDED.role;

-- Cập nhật vai trò Admin cho tài khoản admin@gmail.com nếu đã tồn tại
UPDATE users SET role = 'Admin' WHERE email = 'admin@gmail.com';


-- ============================================================================
-- 2. BẢNG USER_ADDRESSES (Sổ địa chỉ giao hàng)
-- ============================================================================
DELETE FROM user_addresses WHERE id IN (
    '44444444-0000-0000-0000-000000000001',
    '44444444-0000-0000-0000-000000000002',
    '44444444-0000-0000-0000-000000000003',
    '44444444-0000-0000-0000-000000000004',
    '44444444-0000-0000-0000-000000000005'
);

INSERT INTO user_addresses (id, firebase_uid, user_id, label, recipient_name, phone_number, full_address, note, is_default, created_at)
VALUES
    -- Địa chỉ cho khách hàng mẫu 1
    ('44444444-0000-0000-0000-000000000001', 'customer_sample_01', '33333333-0000-0000-0000-000000000001', 'Nhà riêng', 'Nguyễn Thu Trang', '0988776655', '123 Lê Lợi, Phường Bến Nghé, Quận 1, TP. Hồ Chí Minh', 'Giao tận cửa lầu 2, bấm chuông giúp mình', true, NOW()),
    ('44444444-0000-0000-0000-000000000002', 'customer_sample_01', '33333333-0000-0000-0000-000000000001', 'Công ty', 'Thu Trang (SOOPI Office)', '0988776655', 'Tòa nhà Bitexco Financial Tower, 2 Hải Triều, Bến Nghé, Quận 1, TP. Hồ Chí Minh', 'Gửi lễ tân tầng trệt', false, NOW()),
    ('44444444-0000-0000-0000-000000000003', 'customer_sample_01', '33333333-0000-0000-0000-000000000001', 'Nhà bố mẹ', 'Cô Lan', '0918889999', '456 Nguyễn Đình Chiểu, Phường 4, Quận 3, TP. Hồ Chí Minh', 'Hẻm rộng ôtô vào được', false, NOW());

-- Thêm địa chỉ cho các tài khoản test hiện có (nếu tồn tại trong bảng users)
INSERT INTO user_addresses (id, firebase_uid, user_id, label, recipient_name, phone_number, full_address, note, is_default, created_at)
SELECT 
    '44444444-0000-0000-0000-000000000004'::uuid,
    u.firebase_uid,
    u.id,
    'Nhà riêng',
    u.full_name,
    COALESCE(u.phone_number, '0909123456'),
    '72 Lê Thánh Tôn, Phường Bến Nghé, Quận 1, TP. Hồ Chí Minh',
    'Gọi trước khi giao',
    true,
    NOW()
FROM users u
WHERE u.email = 'test_user_01@soopi.vn' OR u.firebase_uid = 'test_user_01'
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_addresses (id, firebase_uid, user_id, label, recipient_name, phone_number, full_address, note, is_default, created_at)
SELECT 
    '44444444-0000-0000-0000-000000000005'::uuid,
    u.firebase_uid,
    u.id,
    'Nhà riêng',
    u.full_name,
    COALESCE(u.phone_number, '0938112233'),
    '15 Bis Nguyễn Thị Minh Khai, Phường Bến Nghé, Quận 1, TP. Hồ Chí Minh',
    'Nhà mặt tiền',
    true,
    NOW()
FROM users u
WHERE u.email IN ('admin@gmail.com', 'tant91468@gmail.com', 'check@gmail.com')
LIMIT 1
ON CONFLICT (id) DO NOTHING;


-- ============================================================================
-- 3. BẢNG "Restaurants" (Danh sách quán ăn / nhà hàng)
-- ============================================================================
INSERT INTO "Restaurants" ("Id", "OwnerId", "Name", "Description", "Phone", "Address", "City", "ImageUrl", "Latitude", "Longitude", "AverageRating", "ReviewCount", "TotalOrders", "IsActive", "IsAcceptingOrders")
VALUES
    -- 1. Burger
    (
        '55555555-0000-0000-0000-000000000001',
        '11111111-0000-0000-0000-000000000001',
        'The Burger Lab - Bò Nướng Tảng',
        'Burger bò Wagyu hảo hạng 100%, nướng trên than hoa kèm sốt phô mai cheddar tan chảy và khoai tây giòn rụm.',
        '02838221199',
        '15 Đặng Thị Nhu, Phường Nguyễn Thái Bình, Quận 1',
        'Hồ Chí Minh',
        'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=800&auto=format&fit=crop',
        10.7698500,
        106.6965000,
        4.85,
        312,
        1420,
        true,
        true
    ),
    -- 2. Pizza
    (
        '55555555-0000-0000-0000-000000000002',
        '11111111-0000-0000-0000-000000000002',
        'Pizza 4P''s - Hai Bà Trưng',
        'Pizza nướng lò củi kiểu Napoli truyền thống, phô mai Burrata tươi béo ngậy thủ công và mỳ Ý cua danh tiếng.',
        '02836220500',
        '151 Hai Bà Trưng, Phường 6, Quận 3',
        'Hồ Chí Minh',
        'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=800&auto=format&fit=crop',
        10.7834200,
        106.6953200,
        4.92,
        890,
        3250,
        true,
        true
    ),
    -- 3. Sushi
    (
        '55555555-0000-0000-0000-000000000003',
        '11111111-0000-0000-0000-000000000003',
        'Sushi Tei - Tinh Hoa Ẩm Thực Nhật',
        'Sashimi cá hồi Na Uy tươi nguyên con mỗi ngày, Nigiri bò Wagyu dát vàng và cơm cuộn hải sản thượng hạng.',
        '02862841188',
        '200 Lý Tự Trọng, Phường Bến Thành, Quận 1',
        'Hồ Chí Minh',
        'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=800&auto=format&fit=crop',
        10.7725800,
        106.6934500,
        4.78,
        420,
        1850,
        true,
        true
    ),
    -- 4. Đồ uống
    (
        '55555555-0000-0000-0000-000000000004',
        '11111111-0000-0000-0000-000000000004',
        'Phúc Long Coffee & Tea - Ngô Đức Kế',
        'Trà đào cam sả đặc sản đậm vị trà, trà sữa ô long nướng thơm béo cùng hạt sen giòn ngọt nức tiếng Sài Gòn.',
        '02838248333',
        '29 Ngô Đức Kế, Phường Bến Nghé, Quận 1',
        'Hồ Chí Minh',
        'https://images.unsplash.com/photo-1556881286-fc6915169721?w=800&auto=format&fit=crop',
        10.7731200,
        106.7042500,
        4.68,
        650,
        4100,
        true,
        true
    ),
    -- 5. Cơm & Món Việt
    (
        '55555555-0000-0000-0000-000000000005',
        '11111111-0000-0000-0000-000000000005',
        'Cơm Tấm Ba Ghiền - Sườn Cọng Khổng Lồ',
        'Sườn cọng ướp mật ong nướng than hồng ngập tràn đĩa cơm tấm hạt tấm nhuyễn, mỡ hành tóp mỡ béo giòn thơm phức.',
        '02838461073',
        '84 Đặng Văn Ngữ, Phường 10, Quận Phú Nhuận',
        'Hồ Chí Minh',
        'https://images.unsplash.com/photo-1541544741938-0af808871cc0?w=800&auto=format&fit=crop',
        10.7915000,
        106.6742000,
        4.88,
        1100,
        5600,
        true,
        true
    ),
    -- 6. Healthy & Salad
    (
        '55555555-0000-0000-0000-000000000006',
        '11111111-0000-0000-0000-000000000006',
        'Poke Saigon & Healthy Bowl',
        'Tô Poke chuẩn hương vị Hawaii, cá hồi sốt mè rang bùi béo kết hợp bơ sáp Đắk Lắk tươi ngon, chuẩn Eat Clean bổ dưỡng.',
        '0903334455',
        '42 Bis Lý Tự Trọng, Phường Bến Nghé, Quận 1',
        'Hồ Chí Minh',
        'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800&auto=format&fit=crop',
        10.7774000,
        106.7001000,
        4.72,
        280,
        950,
        true,
        true
    )
ON CONFLICT ("Id") DO UPDATE
SET "Name" = EXCLUDED."Name",
    "Description" = EXCLUDED."Description",
    "Address" = EXCLUDED."Address",
    "ImageUrl" = EXCLUDED."ImageUrl",
    "AverageRating" = EXCLUDED."AverageRating",
    "ReviewCount" = EXCLUDED."ReviewCount",
    "TotalOrders" = EXCLUDED."TotalOrders",
    "IsActive" = EXCLUDED."IsActive",
    "IsAcceptingOrders" = EXCLUDED."IsAcceptingOrders";


-- ============================================================================
-- 4. BẢNG "OpeningHours" (Giờ mở cửa cho các nhà hàng: 7 ngày trong tuần)
-- ============================================================================
-- 0 = Chủ Nhật, 1 = Thứ 2, ..., 6 = Thứ 7
INSERT INTO "OpeningHours" ("Id", "RestaurantId", "DayOfWeek", "OpensAt", "ClosesAt", "IsClosed")
VALUES
    -- The Burger Lab (7 ngày)
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000001', 0, '08:00:00', '23:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000001', 1, '08:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000001', 2, '08:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000001', 3, '08:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000001', 4, '08:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000001', 5, '08:00:00', '23:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000001', 6, '08:00:00', '23:00:00', false),

    -- Pizza 4P's (7 ngày)
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000002', 0, '09:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000002', 1, '09:00:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000002', 2, '09:00:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000002', 3, '09:00:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000002', 4, '09:00:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000002', 5, '09:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000002', 6, '09:00:00', '22:30:00', false),

    -- Sushi Tei (7 ngày)
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000003', 0, '10:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000003', 1, '10:00:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000003', 2, '10:00:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000003', 3, '10:00:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000003', 4, '10:00:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000003', 5, '10:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000003', 6, '10:00:00', '22:30:00', false),

    -- Phúc Long (7 ngày)
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000004', 0, '07:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000004', 1, '07:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000004', 2, '07:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000004', 3, '07:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000004', 4, '07:00:00', '22:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000004', 5, '07:00:00', '23:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000004', 6, '07:00:00', '23:00:00', false),

    -- Cơm Tấm Ba Ghiền (7 ngày)
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000005', 0, '06:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000005', 1, '06:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000005', 2, '06:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000005', 3, '06:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000005', 4, '06:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000005', 5, '06:30:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000005', 6, '06:30:00', '22:00:00', false),

    -- Poke Saigon (7 ngày)
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000006', 0, '09:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000006', 1, '09:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000006', 2, '09:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000006', 3, '09:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000006', 4, '09:30:00', '21:30:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000006', 5, '09:30:00', '22:00:00', false),
    (gen_random_uuid(), '55555555-0000-0000-0000-000000000006', 6, '09:30:00', '22:00:00', false)
ON CONFLICT ("RestaurantId", "DayOfWeek") DO UPDATE
SET "OpensAt" = EXCLUDED."OpensAt",
    "ClosesAt" = EXCLUDED."ClosesAt",
    "IsClosed" = EXCLUDED."IsClosed";


-- ============================================================================
-- 5. BẢNG "MenuCategories" (Danh mục món ăn của từng quán)
-- ============================================================================
INSERT INTO "MenuCategories" ("Id", "RestaurantId", "Name", "SortOrder")
VALUES
    -- The Burger Lab (Danh mục chứa từ khóa 'Burger' để match bộ lọc Home)
    ('66666666-0001-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', 'Burger Bò & Phô Mai', 1),
    ('66666666-0001-0000-0000-000000000002', '55555555-0000-0000-0000-000000000001', 'Burger Gà Giòn Cay', 2),
    ('66666666-0001-0000-0000-000000000003', '55555555-0000-0000-0000-000000000001', 'Khoai Tây & Ăn Kèm', 3),
    ('66666666-0001-0000-0000-000000000004', '55555555-0000-0000-0000-000000000001', 'Đồ Uống Có Ga', 4),

    -- Pizza 4P's (Danh mục chứa từ khóa 'Pizza' để match bộ lọc Home)
    ('66666666-0002-0000-0000-000000000001', '55555555-0000-0000-0000-000000000002', 'Pizza Nướng Lò Củi', 1),
    ('66666666-0002-0000-0000-000000000002', '55555555-0000-0000-0000-000000000002', 'Mỳ Ý Thủ Công (Pasta)', 2),
    ('66666666-0002-0000-0000-000000000003', '55555555-0000-0000-0000-000000000002', 'Khai Vị & Phô Mai Tươi', 3),
    ('66666666-0002-0000-0000-000000000004', '55555555-0000-0000-0000-000000000002', 'Đồ Uống & Tráng Miệng', 4),

    -- Sushi Tei (Danh mục chứa từ khóa 'Sushi' để match bộ lọc Home)
    ('66666666-0003-0000-0000-000000000001', '55555555-0000-0000-0000-000000000003', 'Sushi Nigiri & Gunkan', 1),
    ('66666666-0003-0000-0000-000000000002', '55555555-0000-0000-0000-000000000003', 'Sashimi Tươi Sống', 2),
    ('66666666-0003-0000-0000-000000000003', '55555555-0000-0000-0000-000000000003', 'Cơm Cuộn Sushi Roll', 3),
    ('66666666-0003-0000-0000-000000000004', '55555555-0000-0000-0000-000000000003', 'Trà Nhật & Khai Vị', 4),

    -- Phúc Long (Danh mục chứa từ khóa 'Đồ uống' để match bộ lọc Home)
    ('66666666-0004-0000-0000-000000000001', '55555555-0000-0000-0000-000000000004', 'Đồ Uống Trà Trái Cây', 1),
    ('66666666-0004-0000-0000-000000000002', '55555555-0000-0000-0000-000000000004', 'Đồ Uống Trà Sữa Đậm Vị', 2),
    ('66666666-0004-0000-0000-000000000003', '55555555-0000-0000-0000-000000000004', 'Cà Phê & Đá Xay', 3),
    ('66666666-0004-0000-0000-000000000004', '55555555-0000-0000-0000-000000000004', 'Bánh Ngọt Bakery', 4),

    -- Cơm Tấm Ba Ghiền (Món Việt truyền thống)
    ('66666666-0005-0000-0000-000000000001', '55555555-0000-0000-0000-000000000005', 'Cơm Tấm Đặc Biệt', 1),
    ('66666666-0005-0000-0000-000000000002', '55555555-0000-0000-0000-000000000005', 'Món Gọi Thêm', 2),
    ('66666666-0005-0000-0000-000000000003', '55555555-0000-0000-0000-000000000005', 'Canh Nóng & Nước Giải Khát', 3),

    -- Poke Saigon (Danh mục chứa từ khóa 'Healthy' để match bộ lọc Home)
    ('66666666-0006-0000-0000-000000000001', '55555555-0000-0000-0000-000000000006', 'Healthy Poke Bowl', 1),
    ('66666666-0006-0000-0000-000000000002', '55555555-0000-0000-0000-000000000006', 'Healthy Salad Eat Clean', 2),
    ('66666666-0006-0000-0000-000000000003', '55555555-0000-0000-0000-000000000006', 'Nước Ép Trái Cây Detox', 3)
ON CONFLICT ("Id") DO UPDATE
SET "Name" = EXCLUDED."Name",
    "SortOrder" = EXCLUDED."SortOrder";


-- ============================================================================
-- 6. BẢNG "MenuItems" (Món ăn / thức uống chi tiết)
-- ============================================================================
INSERT INTO "MenuItems" ("Id", "CategoryId", "Name", "Description", "Price", "OriginalPrice", "DiscountPercent", "ImageUrl", "SoldCount", "LikesCount", "IsAvailable")
VALUES
    -- The Burger Lab
    (
        '77777777-0001-0000-0000-000000000001',
        '66666666-0001-0000-0000-000000000001',
        'Burger Bò Phô Mai Double',
        '2 lớp thịt bò Wagyu áp chảo, phô mai Cheddar kép tan chảy, hành tây caramen và dưa chuột muối giòn ngọt.',
        89000, 110000, 19,
        'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=600&auto=format&fit=crop',
        380, 156, true
    ),
    (
        '77777777-0001-0000-0000-000000000002',
        '66666666-0001-0000-0000-000000000001',
        'Burger Bò Nấm Truffle Cao Cấp',
        'Bò Úc thượng hạng kết hợp nấm mỡ xào bơ tỏi và sốt dầu nấm Truffle đen quý giá dậy mùi ngây ngất.',
        115000, 135000, 15,
        'https://images.unsplash.com/photo-1586190848861-99aa4a171e90?w=600&auto=format&fit=crop',
        210, 94, true
    ),
    (
        '77777777-0001-0000-0000-000000000003',
        '66666666-0001-0000-0000-000000000001',
        'Burger Bò Xông Khói Bacon BBQ',
        'Thịt bò đập dập thơm lừng kèm thịt xông khói áp chảo giòn tan quyện sốt BBQ thơm khói đặc trưng phong cách Mỹ.',
        99000, 120000, 18,
        'https://images.unsplash.com/photo-1550547660-d9450f859349?w=600&auto=format&fit=crop',
        185, 78, true
    ),
    (
        '77777777-0001-0000-0000-000000000004',
        '66666666-0001-0000-0000-000000000002',
        'Burger Gà Giòn Sốt Cay Hàn Quốc',
        'Ức gà tươi tẩm bột chiên giòn rụm bên ngoài mọng nước bên trong, phủ sốt cay ngọt Gochujang rắc mè trắng.',
        75000, 89000, 16,
        'https://images.unsplash.com/photo-1625813506062-0aeb1d7a094b?w=600&auto=format&fit=crop',
        290, 112, true
    ),
    (
        '77777777-0001-0000-0000-000000000005',
        '66666666-0001-0000-0000-000000000003',
        'Khoai Tây Chiên Lắc Phô Mai',
        'Khoai tây sợi Bỉ chiên vàng ươm, lắc đều cùng bột phô mai mặn ngọt béo ngậy.',
        35000, 42000, 17,
        'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=600&auto=format&fit=crop',
        520, 240, true
    ),
    (
        '77777777-0001-0000-0000-000000000006',
        '66666666-0001-0000-0000-000000000004',
        'Coca Cola Tươi Lon 330ml',
        'Nước ngọt có ga ướp lạnh sảng khoái.',
        18000, 20000, 10,
        'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?w=600&auto=format&fit=crop',
        410, 89, true
    ),

    -- Pizza 4P's
    (
        '77777777-0002-0000-0000-000000000001',
        '66666666-0002-0000-0000-000000000001',
        'Pizza 4 Loại Phô Mai (4 Cheese Pizza)',
        'Sự kết hợp hoàn mỹ từ Mozzarella, Gorgonzola, Ricotta, Parmesan kèm mật ong nguyên chất rưới lên khi ăn nóng.',
        195000, 220000, 11,
        'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=600&auto=format&fit=crop',
        750, 430, true
    ),
    (
        '77777777-0002-0000-0000-000000000002',
        '66666666-0002-0000-0000-000000000001',
        'Pizza Hải Sản Sốt Cà San Marzano',
        'Tôm sú, mực tươi, nghêu ngọt kết hợp phô mai xông khói nướng phồng xốp viền bánh.',
        215000, 245000, 12,
        'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=600&auto=format&fit=crop',
        490, 280, true
    ),
    (
        '77777777-0002-0000-0000-000000000003',
        '66666666-0002-0000-0000-000000000002',
        'Mỳ Ý Sốt Cua Cà Chua & Kem Tươi',
        'Món mỳ trứ danh với thịt cua biển Cà Mau gỡ tươi, nước sốt cà chua kem béo ngậy ngọt lịm vị biển.',
        175000, 195000, 10,
        'https://images.unsplash.com/photo-1621996346565-e3d5d6281744?w=600&auto=format&fit=crop',
        680, 395, true
    ),
    (
        '77777777-0002-0000-0000-000000000004',
        '66666666-0002-0000-0000-000000000003',
        'Phô Mai Burrata Tươi & Thịt Xông Khói',
        'Viên phô mai Burrata béo mềm tứa sữa non bên trong ăn kèm quả sung sấy dẻo và giăm bông Parma.',
        155000, 175000, 11,
        'https://images.unsplash.com/photo-1592417817098-8f3d6910985b?w=600&auto=format&fit=crop',
        310, 190, true
    ),
    (
        '77777777-0002-0000-0000-000000000005',
        '66666666-0002-0000-0000-000000000004',
        'Bánh Tiramisu 4P''s Cổ Điển',
        'Bánh Tiramisu mềm mịn thơm mùi cà phê espresso và rượu Kahlua hảo hạng.',
        75000, 85000, 12,
        'https://images.unsplash.com/photo-1571877227200-a0d98ea607e9?w=600&auto=format&fit=crop',
        230, 140, true
    ),

    -- Sushi Tei
    (
        '77777777-0003-0000-0000-000000000001',
        '66666666-0003-0000-0000-000000000001',
        'Nigiri Cá Hồi Na Uy (2 miếng)',
        'Cá hồi tươi phi lê dày dặn đặt trên nắm cơm dẻo trộn giấm truyền thống xứ sở Phù Tang.',
        45000, 52000, 13,
        'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=600&auto=format&fit=crop',
        450, 210, true
    ),
    (
        '77777777-0003-0000-0000-000000000002',
        '66666666-0003-0000-0000-000000000001',
        'Nigiri Lươn Nhật Nướng Unagi (2 miếng)',
        'Lươn biển nướng sốt ngọt Teriyaki óng ả, thịt ngọt mềm tan trong miệng.',
        68000, 78000, 13,
        'https://images.unsplash.com/photo-1617196034796-73dfa7b1fd56?w=600&auto=format&fit=crop',
        320, 160, true
    ),
    (
        '77777777-0003-0000-0000-000000000003',
        '66666666-0003-0000-0000-000000000002',
        'Sashimi Cá Hồi Na Uy Thượng Hạng (5 lát)',
        'Những lát cá hồi tươi sống vân mỡ đều tăm tắp, ăn kèm mù tạt wasabi cay nồng và lá tía tô tươi.',
        125000, 145000, 14,
        'https://images.unsplash.com/photo-1534482421-64566f976cfa?w=600&auto=format&fit=crop',
        610, 380, true
    ),
    (
        '77777777-0003-0000-0000-000000000004',
        '66666666-0003-0000-0000-000000000003',
        'Cơm Cuộn Cầu Vồng Rainbow Roll',
        'Cơm cuộn phủ cá hồi, cá ngừ, quả bơ béo ngậy và trứng tôm Tobiko giòn tanh tách.',
        135000, 160000, 16,
        'https://images.unsplash.com/photo-1563245372-f21724e3856d?w=600&auto=format&fit=crop',
        280, 175, true
    ),

    -- Phúc Long
    (
        '77777777-0004-0000-0000-000000000001',
        '66666666-0004-0000-0000-000000000001',
        'Trà Đào Cam Sả Đặc Biệt (Size L)',
        'Hương trà lài thanh thoát kết hợp miếng đào giòn ngọt lịm, tinh dầu sả tươi và nước cam thơm lừng.',
        55000, 65000, 15,
        'https://images.unsplash.com/photo-1556881286-fc6915169721?w=600&auto=format&fit=crop',
        1520, 890, true
    ),
    (
        '77777777-0004-0000-0000-000000000002',
        '66666666-0004-0000-0000-000000000001',
        'Trà Vải Lài Thanh Khiết (Size L)',
        'Vị trà thanh dịu mùi hoa lài cùng quả vải thiều mọng nước, giải nhiệt ngày hè cực đỉnh.',
        50000, 58000, 14,
        'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=600&auto=format&fit=crop',
        980, 520, true
    ),
    (
        '77777777-0004-0000-0000-000000000003',
        '66666666-0004-0000-0000-000000000002',
        'Trà Sữa Phúc Long Truyền Thống (Size L)',
        'Vị trà đen đậm chất Phúc Long hòa cùng sữa béo thơm, vị chát ngọt đọng mãi nơi cuống họng.',
        48000, 55000, 13,
        'https://images.unsplash.com/photo-1558857563-b37cf54e3d36?w=600&auto=format&fit=crop',
        1850, 1100, true
    ),
    (
        '77777777-0004-0000-0000-000000000004',
        '66666666-0004-0000-0000-000000000002',
        'Trà Sữa Ô Long Nướng Trân Châu',
        'Trà Ô Long sấy than đượm hương khói hòa cùng trân châu đen dẻo dai hoàng kim ngọt mật.',
        52000, 60000, 13,
        'https://images.unsplash.com/photo-1576092768241-dec231879fc3?w=600&auto=format&fit=crop',
        1120, 710, true
    ),
    (
        '77777777-0004-0000-0000-000000000005',
        '66666666-0004-0000-0000-000000000003',
        'Cà Phê Sữa Đá Sài Gòn Đậm Đà',
        'Cà phê Robusta rang xay pha phin truyền thống thơm lừng béo ngọt cùng sữa đặc Ông Thọ.',
        38000, 45000, 16,
        'https://images.unsplash.com/photo-1514432324607-a09d9b4aefdd?w=600&auto=format&fit=crop',
        640, 310, true
    ),

    -- Cơm Tấm Ba Ghiền
    (
        '77777777-0005-0000-0000-000000000001',
        '66666666-0005-0000-0000-000000000001',
        'Cơm Tấm Sườn Cọng Nướng Than Hoa',
        'Cọng sườn heo to bản dày thịt, ướp đậm gia vị nướng trên lửa than hồng vàng ươm ăn kèm đồ chua nước mắm kẹo.',
        65000, 75000, 13,
        'https://images.unsplash.com/photo-1541544741938-0af808871cc0?w=600&auto=format&fit=crop',
        1430, 920, true
    ),
    (
        '77777777-0005-0000-0000-000000000002',
        '66666666-0005-0000-0000-000000000001',
        'Cơm Tấm Sườn Bì Chả Trứng Ốp La (Đặc Biệt)',
        'Đầy đủ các topping truyền thống: sườn nướng, bì heo trộn thính gạo, chả trứng chưng béo ngậy và trứng ốp lòng đào.',
        85000, 95000, 11,
        'https://images.unsplash.com/photo-1569058242253-92a9c755a0ec?w=600&auto=format&fit=crop',
        2100, 1450, true
    ),
    (
        '77777777-0005-0000-0000-000000000003',
        '66666666-0005-0000-0000-000000000002',
        'Chả Trứng Hấp Thịt Béo Bùi',
        'Thịt băm, mộc nhĩ, miến dong trộn trứng gà ta chưng cách thủy mềm mịn thơm ngậy.',
        15000, 18000, 17,
        'https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=600&auto=format&fit=crop',
        520, 210, true
    ),
    (
        '77777777-0005-0000-0000-000000000004',
        '66666666-0005-0000-0000-000000000003',
        'Canh Khổ Qua Nhồi Thịt Nóng Hổi',
        'Khổ qua tươi nấu cùng nước hầm xương thanh mát giải nhiệt, nhân thịt nạc băm nêm nếm vừa miệng.',
        25000, 30000, 17,
        'https://images.unsplash.com/photo-1547592180-85f173990554?w=600&auto=format&fit=crop',
        680, 330, true
    ),

    -- Poke Saigon
    (
        '77777777-0006-0000-0000-000000000001',
        '66666666-0006-0000-0000-000000000001',
        'Poke Bowl Cá Hồi Sốt Mè Rang Béo Bùi',
        'Gạo lứt dẻo, cá hồi Na Uy thái hạt lựu, quả bơ tươi, rong biển wakame, đậu nành edamame và trứng tôm bùi béo.',
        129000, 149000, 13,
        'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600&auto=format&fit=crop',
        390, 215, true
    ),
    (
        '77777777-0006-0000-0000-000000000002',
        '66666666-0006-0000-0000-000000000001',
        'Poke Bowl Bò Úc Áp Chảo & Sốt Teriyaki',
        'Thăn bò Úc ướp mềm áp chảo xì xèo, bắp ngọt hạt, cà chua bi organic và mè rang thơm nức.',
        139000, 159000, 13,
        'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=600&auto=format&fit=crop',
        280, 160, true
    ),
    (
        '77777777-0006-0000-0000-000000000003',
        '66666666-0006-0000-0000-000000000002',
        'Salad Ức Gà Nướng Mật Ong Xốt Chanh Dây',
        'Ức gà nướng mềm mọng nước, xà lách romain giòn ngọt, phô mai feta và sốt chanh leo tươi chua ngọt.',
        89000, 105000, 15,
        'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=600&auto=format&fit=crop',
        310, 180, true
    ),
    (
        '77777777-0006-0000-0000-000000000004',
        '66666666-0006-0000-0000-000000000003',
        'Nước Ép Táo Cà Rốt Cam Tươi Ép Lạnh',
        'Nước ép nguyên chất 100% không thêm đường hay nước, dồi dào vitamin C giúp sáng da thanh lọc cơ thể.',
        45000, 50000, 10,
        'https://images.unsplash.com/photo-1613478223719-2ab802602423?w=600&auto=format&fit=crop',
        420, 260, true
    )
ON CONFLICT ("Id") DO UPDATE
SET "Name" = EXCLUDED."Name",
    "Description" = EXCLUDED."Description",
    "Price" = EXCLUDED."Price",
    "OriginalPrice" = EXCLUDED."OriginalPrice",
    "DiscountPercent" = EXCLUDED."DiscountPercent",
    "ImageUrl" = EXCLUDED."ImageUrl",
    "SoldCount" = EXCLUDED."SoldCount",
    "LikesCount" = EXCLUDED."LikesCount",
    "IsAvailable" = EXCLUDED."IsAvailable";


-- ============================================================================
-- 7. BẢNG "Coupons" (Mã giảm giá phong phú cho khách hàng checkout)
-- ============================================================================
INSERT INTO "Coupons" ("Id", "Code", "DiscountType", "DiscountValue", "MinOrderAmount", "MaxDiscount", "StartsAt", "EndsAt", "UsageLimit", "UsedCount", "IsActive")
VALUES
    -- Giảm %
    ('88888888-0000-0000-0000-000000000001', 'SOOPI50', 'Percent', 50, 100000, 50000, '2024-01-01 00:00:00+07', '2030-12-31 23:59:59+07', 1000, 12, true),
    ('88888888-0000-0000-0000-000000000002', 'BANMOI', 'Percent', 30, 60000, 40000, '2024-01-01 00:00:00+07', '2030-12-31 23:59:59+07', 500, 8, true),
    ('88888888-0000-0000-0000-000000000003', 'WEEKEND', 'Percent', 20, 120000, 35000, '2024-01-01 00:00:00+07', '2030-12-31 23:59:59+07', 800, 15, true),

    -- Giảm tiền cố định (Fixed)
    ('88888888-0000-0000-0000-000000000004', 'FREESHIP', 'Fixed', 25000, 50000, 25000, '2024-01-01 00:00:00+07', '2030-12-31 23:59:59+07', 5000, 48, true),
    ('88888888-0000-0000-0000-000000000005', 'GIAM20K', 'Fixed', 20000, 70000, 20000, '2024-01-01 00:00:00+07', '2030-12-31 23:59:59+07', 1000, 25, true),
    ('88888888-0000-0000-0000-000000000006', 'GIAM50K', 'Fixed', 50000, 180000, 50000, '2024-01-01 00:00:00+07', '2030-12-31 23:59:59+07', 500, 6, true),
    ('88888888-0000-0000-0000-000000000007', 'GIAM100K', 'Fixed', 100000, 350000, 100000, '2024-01-01 00:00:00+07', '2030-12-31 23:59:59+07', 200, 3, true),
    ('88888888-0000-0000-0000-000000000008', 'HELLOSOOPI', 'Fixed', 15000, 40000, 15000, '2024-01-01 00:00:00+07', '2030-12-31 23:59:59+07', 9999, 102, true)
ON CONFLICT ("Code") DO UPDATE
SET "DiscountType" = EXCLUDED."DiscountType",
    "DiscountValue" = EXCLUDED."DiscountValue",
    "MinOrderAmount" = EXCLUDED."MinOrderAmount",
    "MaxDiscount" = EXCLUDED."MaxDiscount",
    "StartsAt" = EXCLUDED."StartsAt",
    "EndsAt" = EXCLUDED."EndsAt",
    "UsageLimit" = EXCLUDED."UsageLimit",
    "IsActive" = EXCLUDED."IsActive";


-- ============================================================================
-- 8. BẢNG "Carts" & "CartItems" (Giỏ hàng mẫu cho khách hàng test)
-- ============================================================================
-- Tạo giỏ hàng mẫu chứa món Burger của The Burger Lab cho khách hàng mẫu
INSERT INTO "Carts" ("Id", "UserId", "RestaurantId", "UpdatedAt")
VALUES
    ('99999999-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', NOW())
ON CONFLICT ("UserId") DO UPDATE
SET "RestaurantId" = EXCLUDED."RestaurantId",
    "UpdatedAt" = EXCLUDED."UpdatedAt";

-- Tạo sẵn giỏ hàng rỗng hoặc gán quán cho user test hiện tại nếu có
INSERT INTO "Carts" ("Id", "UserId", "RestaurantId", "UpdatedAt")
SELECT 
    gen_random_uuid(),
    u.id,
    '55555555-0000-0000-0000-000000000001'::uuid,
    NOW()
FROM users u
WHERE u.role = 'Customer' AND u.id != '33333333-0000-0000-0000-000000000001'
ON CONFLICT ("UserId") DO NOTHING;

-- Chèn món vào giỏ hàng mẫu của khách hàng mẫu
DELETE FROM "CartItems" WHERE "CartId" = '99999999-0000-0000-0000-000000000001';

INSERT INTO "CartItems" ("Id", "CartId", "MenuItemId", "Quantity", "Note")
VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000001', '77777777-0001-0000-0000-000000000001', 1, 'Bỏ ít dưa chuột muối, thêm sốt phô mai'),
    ('aaaaaaaa-0000-0000-0000-000000000002', '99999999-0000-0000-0000-000000000001', '77777777-0001-0000-0000-000000000005', 1, 'Chiên giòn, bột phô mai riêng')
ON CONFLICT ("CartId", "MenuItemId") DO UPDATE
SET "Quantity" = EXCLUDED."Quantity",
    "Note" = EXCLUDED."Note";


-- ============================================================================
-- 9. BẢNG "Favorites" (Quán ăn yêu thích)
-- ============================================================================
INSERT INTO "Favorites" ("Id", "UserId", "RestaurantId", "CreatedAt")
VALUES
    (gen_random_uuid(), '33333333-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', NOW()),
    (gen_random_uuid(), '33333333-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000002', NOW()),
    (gen_random_uuid(), '33333333-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000004', NOW()),
    (gen_random_uuid(), '33333333-0000-0000-0000-000000000002', '55555555-0000-0000-0000-000000000003', NOW()),
    (gen_random_uuid(), '33333333-0000-0000-0000-000000000002', '55555555-0000-0000-0000-000000000006', NOW())
ON CONFLICT ("UserId", "RestaurantId") DO NOTHING;

-- Thêm yêu thích cho các user customer hiện tại nếu có
INSERT INTO "Favorites" ("Id", "UserId", "RestaurantId", "CreatedAt")
SELECT 
    gen_random_uuid(),
    u.id,
    '55555555-0000-0000-0000-000000000001'::uuid,
    NOW()
FROM users u
WHERE u.role = 'Customer' AND u.id NOT IN ('33333333-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000003')
ON CONFLICT ("UserId", "RestaurantId") DO NOTHING;

COMMIT;
``
-- ============================================================================
-- HOÀN TẤT NẠP DỮ LIỆU SEED!
-- Các bảng Order (Orders, OrderItems, OrderStatusHistory, Payments, 
-- Reviews, DeliveryLocations) được để trống hoàn toàn để bạn tự thao tác test.
-- ============================================================================
