CREATE TABLE IF NOT EXISTS platform_users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(191) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  display_name VARCHAR(120) NOT NULL,
  role ENUM('reader', 'author', 'admin') NOT NULL,
  status ENUM('pending', 'active', 'suspended') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_platform_users_email (email),
  KEY ix_platform_users_role_status (role, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS platform_books (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  author_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(200) NOT NULL,
  description TEXT NOT NULL,
  price_amount DECIMAL(14, 2) UNSIGNED NOT NULL,
  currency CHAR(3) NOT NULL,
  storage_key CHAR(36) NOT NULL,
  original_file_name VARCHAR(255) NOT NULL,
  file_type ENUM('pdf', 'docx') NOT NULL,
  file_size_bytes INT UNSIGNED NOT NULL,
  status ENUM('pending', 'approved', 'rejected') NOT NULL DEFAULT 'pending',
  review_note VARCHAR(1000) NULL,
  reviewed_by BIGINT UNSIGNED NULL,
  reviewed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_platform_books_storage_key (storage_key),
  KEY ix_platform_books_status_created (status, created_at),
  KEY ix_platform_books_author_created (author_id, created_at),
  CONSTRAINT fk_platform_books_author
    FOREIGN KEY (author_id) REFERENCES platform_users (id) ON DELETE RESTRICT,
  CONSTRAINT fk_platform_books_reviewer
    FOREIGN KEY (reviewed_by) REFERENCES platform_users (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS platform_settings (
  setting_key VARCHAR(100) NOT NULL PRIMARY KEY,
  setting_value VARCHAR(100) NULL,
  updated_by BIGINT UNSIGNED NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_platform_settings_updater
    FOREIGN KEY (updated_by) REFERENCES platform_users (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO platform_settings (setting_key, setting_value)
VALUES ('commission_percent', NULL);

CREATE TABLE IF NOT EXISTS platform_orders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  buyer_id BIGINT UNSIGNED NOT NULL,
  book_id BIGINT UNSIGNED NOT NULL,
  amount DECIMAL(14, 2) UNSIGNED NOT NULL,
  platform_fee DECIMAL(14, 2) UNSIGNED NULL,
  seller_payout DECIMAL(14, 2) UNSIGNED NULL,
  commission_percent DECIMAL(5, 2) UNSIGNED NULL,
  currency CHAR(3) NOT NULL,
  status ENUM('pending_payment', 'paid', 'failed', 'refunded') NOT NULL DEFAULT 'pending_payment',
  payment_provider VARCHAR(60) NULL,
  provider_reference VARCHAR(190) NULL,
  paid_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_platform_orders_provider_reference (provider_reference),
  KEY ix_platform_orders_buyer_status (buyer_id, status),
  KEY ix_platform_orders_book_status (book_id, status),
  KEY ix_platform_orders_created (created_at),
  CONSTRAINT fk_platform_orders_buyer
    FOREIGN KEY (buyer_id) REFERENCES platform_users (id) ON DELETE RESTRICT,
  CONSTRAINT fk_platform_orders_book
    FOREIGN KEY (book_id) REFERENCES platform_books (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
