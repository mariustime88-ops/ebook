import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { loadDatabaseConfig } from '../config.js';
import { createPool } from '../db/pool.js';

const adminSchema = z.object({
  ADMIN_INITIAL_EMAIL: z.string().trim().email().max(191).transform((value) => value.toLowerCase()),
  ADMIN_INITIAL_DISPLAY_NAME: z.string().trim().min(2).max(120),
  ADMIN_INITIAL_PASSWORD: z.string().min(8).max(128),
});

let pool;
try {
  const values = adminSchema.parse(process.env);
  const database = loadDatabaseConfig();
  pool = createPool(database);
  const passwordHash = await bcrypt.hash(values.ADMIN_INITIAL_PASSWORD, 12);
  await pool.execute(
    `INSERT INTO platform_users
      (email, password_hash, display_name, role, status)
     VALUES (?, ?, ?, 'admin', 'active')`,
    [
      values.ADMIN_INITIAL_EMAIL,
      passwordHash,
      values.ADMIN_INITIAL_DISPLAY_NAME,
    ],
  );
  console.info('Compte administrateur créé.');
} catch (error) {
  if (error.code === 'ER_DUP_ENTRY') {
    console.error('Cette adresse e-mail existe déjà. Aucun administrateur créé.');
  } else {
    console.error(`Création de l’administrateur impossible : ${error.message}`);
  }
  process.exitCode = 1;
} finally {
  await pool?.end();
}
