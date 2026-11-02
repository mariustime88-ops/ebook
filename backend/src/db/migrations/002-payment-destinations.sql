ALTER TABLE platform_users
  ADD COLUMN payout_name VARCHAR(120) NULL,
  ADD COLUMN payout_phone VARCHAR(25) NULL;

CREATE TABLE IF NOT EXISTS platform_payment_settings (
  id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
  provider VARCHAR(60) NOT NULL,
  country_code CHAR(2) NOT NULL,
  currency CHAR(3) NOT NULL,
  recipient_name VARCHAR(120) NULL,
  recipient_phone VARCHAR(25) NULL,
  updated_by BIGINT UNSIGNED NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_platform_payment_settings_updater
    FOREIGN KEY (updated_by) REFERENCES platform_users (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO platform_payment_settings
  (id, provider, country_code, currency)
VALUES (1, 'MTN MoMo', 'BJ', 'XOF');
