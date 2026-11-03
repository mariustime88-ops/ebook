ALTER TABLE platform_books
  MODIFY COLUMN status ENUM('pending', 'approved', 'rejected', 'archived')
    NOT NULL DEFAULT 'approved',
  ADD COLUMN cover_mime_type VARCHAR(32) NULL AFTER file_type;

UPDATE platform_books
SET status = 'approved'
WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS platform_book_file_chunks (
  book_id BIGINT UNSIGNED NOT NULL,
  file_kind ENUM('document', 'cover') NOT NULL,
  chunk_index INT UNSIGNED NOT NULL,
  file_data MEDIUMBLOB NOT NULL,
  PRIMARY KEY (book_id, file_kind, chunk_index),
  CONSTRAINT fk_platform_book_file_chunks_book
    FOREIGN KEY (book_id) REFERENCES platform_books (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS platform_password_reset_tokens (
  token_hash CHAR(64) NOT NULL PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  expires_at DATETIME NOT NULL,
  consumed_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY ix_platform_password_reset_user_created (user_id, created_at),
  KEY ix_platform_password_reset_expiry (expires_at),
  CONSTRAINT fk_platform_password_reset_user
    FOREIGN KEY (user_id) REFERENCES platform_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
