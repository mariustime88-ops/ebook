import { createReadStream } from 'node:fs';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { runMigrations } from '../db/migrate.js';
import { loadDatabaseConfig } from '../config.js';
import { createPool } from '../db/pool.js';

const fileChunkSize = 512 * 1024;
const privateBooksDirectory = path.resolve(
  process.cwd(),
  process.env.PRIVATE_FILES_DIR || './private-storage',
  'books',
);
const tables = [
  'platform_users',
  'platform_books',
  'platform_settings',
  'platform_orders',
];

function destinationConfig() {
  return loadDatabaseConfig({
    MYSQL_HOST: process.env.CLOUD_MYSQL_HOST,
    MYSQL_PORT: process.env.CLOUD_MYSQL_PORT || '4000',
    MYSQL_DATABASE: process.env.CLOUD_MYSQL_DATABASE,
    MYSQL_USER: process.env.CLOUD_MYSQL_USER,
    MYSQL_PASSWORD: process.env.CLOUD_MYSQL_PASSWORD,
    MYSQL_SSL: 'true',
  });
}

async function assertDestinationIsEmpty(pool) {
  const placeholders = tables.map(() => '?').join(', ');
  const [existingTables] = await pool.execute(
    `SELECT TABLE_NAME FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (${placeholders})`,
    tables,
  );
  const existingNames = new Set(existingTables.map((row) => row.TABLE_NAME));

  for (const table of tables) {
    if (!existingNames.has(table)) continue;
    if (table === 'platform_settings') {
      const [settings] = await pool.execute(
        'SELECT setting_key, setting_value FROM platform_settings',
      );
      if (
        settings.some(
          (setting) => setting.setting_key !== 'commission_percent'
            || setting.setting_value !== null,
        )
      ) {
        throw new Error(
          'La base cloud contient déjà des paramètres. Aucune donnée n’a été modifiée.',
        );
      }
      continue;
    }

    const [[{ count }]] = await pool.execute(
      `SELECT COUNT(*) AS count FROM \`${table}\``,
    );
    if (Number(count) > 0) {
      throw new Error(
        `La table cloud ${table} contient déjà des données. Aucune donnée n’a été modifiée.`,
      );
    }
  }
}

async function copyTable(source, destination, connection, table) {
  const [rows] = await source.query(`SELECT * FROM \`${table}\``);
  if (rows.length === 0) return 0;

  const columns = Object.keys(rows[0]);
  const quotedColumns = columns.map((column) => `\`${column}\``).join(', ');
  const placeholders = columns.map(() => '?').join(', ');
  const settingsUpdate = table === 'platform_settings'
    ? ` ON DUPLICATE KEY UPDATE ${columns
      .filter((column) => column !== 'setting_key')
      .map((column) => `\`${column}\` = ?`)
      .join(', ')}`
    : '';
  const statement = `INSERT INTO \`${table}\` (${quotedColumns})
    VALUES (${placeholders})${settingsUpdate}`;

  for (const row of rows) {
    const values = columns.map((column) => {
      if (table === 'platform_books' && column === 'status' && row.status === 'pending') {
        return 'approved';
      }
      return row[column];
    });
    const updates = table === 'platform_settings'
      ? columns
        .filter((column) => column !== 'setting_key')
        .map((column) => row[column])
      : [];
    await connection.execute(statement, [...values, ...updates]);
  }

  return rows.length;
}

async function copyBookFiles(source, connection) {
  const [books] = await source.query(
    'SELECT id, storage_key, file_type FROM platform_books ORDER BY id',
  );
  let copied = 0;
  for (const book of books) {
    const extension = book.file_type === 'pdf' ? '.pdf' : '.docx';
    const filePath = path.join(
      privateBooksDirectory,
      `${book.storage_key}${extension}`,
    );
    try {
      await access(filePath);
    } catch (error) {
      if (error.code === 'ENOENT') {
        throw new Error(
          `Le fichier local du livre ${book.id} est introuvable. Aucune donnée cloud n’a été copiée.`,
        );
      }
      throw error;
    }

    let chunkIndex = 0;
    for await (const chunk of createReadStream(filePath, {
      highWaterMark: fileChunkSize,
    })) {
      await connection.execute(
        `INSERT INTO platform_book_file_chunks
          (book_id, file_kind, chunk_index, file_data)
         VALUES (?, 'document', ?, ?)`,
        [book.id, chunkIndex, chunk],
      );
      chunkIndex += 1;
    }
    copied += 1;
  }
  return copied;
}

async function main() {
  const source = createPool(loadDatabaseConfig());
  const destination = createPool(destinationConfig());
  let connection;

  try {
    await source.execute('SELECT 1');
    await destination.execute('SELECT 1');
    await assertDestinationIsEmpty(destination);
    await runMigrations(destination);

    connection = await destination.getConnection();
    await connection.beginTransaction();
    const copied = {};
    for (const table of tables) {
      copied[table] = await copyTable(source, destination, connection, table);
    }
    copied.bookFiles = await copyBookFiles(source, connection);
    await connection.commit();

    console.info(
      `Migration terminée : ${copied.platform_users} comptes, `
      + `${copied.platform_books} livres, `
      + `${copied.bookFiles} fichiers de livres, `
      + `${copied.platform_settings} paramètres et `
      + `${copied.platform_orders} commandes copiés.`,
    );
  } catch (error) {
    if (connection) await connection.rollback();
    console.error(`Échec de la migration des données : ${error.message}`);
    process.exitCode = 1;
  } finally {
    connection?.release();
    await Promise.all([source.end(), destination.end()]);
  }
}

await main();
