-- =======================================================
-- SOOPI FOOD DATABASE SCHEMA (PostgreSQL)
-- Host: localhost:5432 | Database: soopi
-- =======================================================

-- 1. Bảng lưu trữ Người dùng (Users)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid VARCHAR(128) NOT NULL UNIQUE,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL,
    phone_number VARCHAR(20),
    avatar_url VARCHAR(500),
    gender VARCHAR(20) DEFAULT 'Nam',
    date_of_birth TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ,
    role VARCHAR(20) NOT NULL DEFAULT 'Customer',
    is_locked BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS "IX_users_firebase_uid" ON users (firebase_uid);
CREATE INDEX IF NOT EXISTS "IX_users_email" ON users (email);

-- 2. Bảng lưu trữ Sổ địa chỉ giao hàng (User Addresses)
CREATE TABLE IF NOT EXISTS user_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid VARCHAR(128) NOT NULL,
    user_id UUID,
    label VARCHAR(50) NOT NULL DEFAULT 'Nhà riêng',
    recipient_name VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    full_address VARCHAR(500) NOT NULL,
    note VARCHAR(255),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ,
    CONSTRAINT "FK_user_addresses_users_user_id" 
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "IX_user_addresses_firebase_uid" ON user_addresses (firebase_uid);
CREATE INDEX IF NOT EXISTS "IX_user_addresses_user_id" ON user_addresses (user_id);
