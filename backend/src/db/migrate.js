import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadDatabaseConfig } from '../config.js';
import { createPool } from './pool.js';

const migrationDirectory = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  'migrations',
);

function splitStatements(contents) {
  return contents
    .split(/;\s*(?:\r?\n|$)/)
    .map((statement) => statement.trim())
    .filter(Boolean);
}

export async function runMigrations(pool) {
  await pool.execute(`
    CREATE TABLE IF NOT EXISTS platform_schema_migrations (
      migration_name VARCHAR(190) NOT NULL PRIMARY KEY,
      applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  const migrationNames = (await readdir(migrationDirectory))
    .filter((name) => name.endsWith('.sql'))
    .sort();

  for (const migrationName of migrationNames) {
    const [existing] = await pool.execute(
      'SELECT migration_name FROM platform_schema_migrations WHERE migration_name = ?',
      [migrationName],
    );
    if (existing.length > 0) {
      console.info(`Déjà appliquée : ${migrationName}`);
      continue;
    }

    const contents = await readFile(
      path.join(migrationDirectory, migrationName),
      'utf8',
    );
    for (const statement of splitStatements(contents)) {
      await pool.query(statement);
    }
    await pool.execute(
      'INSERT INTO platform_schema_migrations (migration_name) VALUES (?)',
      [migrationName],
    );
    console.info(`Appliquée : ${migrationName}`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let pool;
  try {
    pool = createPool(loadDatabaseConfig());
    await runMigrations(pool);
  } catch (error) {
    console.error(`Échec des migrations : ${error.message}`);
    process.exitCode = 1;
  } finally {
    await pool?.end();
  }
}
