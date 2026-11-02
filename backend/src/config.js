import 'dotenv/config';
import { z } from 'zod';

const databaseSchema = z.object({
  MYSQL_HOST: z.string().min(1).default('127.0.0.1'),
  MYSQL_PORT: z.coerce.number().int().min(1).max(65535).default(3306),
  MYSQL_DATABASE: z.string().min(1).default('ebook'),
  MYSQL_USER: z.string().min(1, 'MYSQL_USER est obligatoire.'),
  MYSQL_PASSWORD: z.string().default(''),
  MYSQL_SSL: z.enum(['true', 'false']).default('false')
    .transform((value) => value === 'true'),
});

export function loadDatabaseConfig(env = process.env) {
  return databaseSchema.parse(env);
}

const serverSchema = databaseSchema.extend({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().min(1).default('127.0.0.1'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  JWT_SECRET: z
    .string()
    .min(32, 'JWT_SECRET doit contenir au moins 32 caractères.'),
  CORS_ORIGINS: z
    .string()
    .default(
      'http://localhost:5013,http://127.0.0.1:5013,http://localhost:5014,http://127.0.0.1:5014',
    ),
  PRIVATE_FILES_DIR: z.string().default('./private-storage'),
  FEDAPAY_SECRET_KEY: z.preprocess(
    (value) => value === '' ? undefined : value,
    z.string()
      .regex(
        /^sk_sandbox_.+/,
        'FEDAPAY_SECRET_KEY doit être une clé secrète sandbox commençant par sk_sandbox_.',
      )
      .optional(),
  ),
  FEDAPAY_ENVIRONMENT: z.literal('sandbox').default('sandbox'),
  FEDAPAY_CALLBACK_URL: z.preprocess(
    (value) => value === '' ? undefined : value,
    z.string().url().optional(),
  ),
});

export function loadServerConfig(env = process.env) {
  const config = serverSchema.parse(env);
  if (config.NODE_ENV === 'production' && config.MYSQL_PASSWORD.length === 0) {
    throw new Error('MYSQL_PASSWORD est obligatoire en production.');
  }

  return {
    ...config,
    corsOrigins: config.CORS_ORIGINS.split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
  };
}
