ALTER TABLE platform_users
  DROP COLUMN payout_name,
  DROP COLUMN payout_phone;

DROP TABLE IF EXISTS platform_payment_settings;
