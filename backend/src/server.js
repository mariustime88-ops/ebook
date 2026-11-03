import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from './http/routes.js';
import { loadServerConfig } from './config.js';
import { createPool } from './db/pool.js';
import { createFedaPayClient } from './payments/fedapay.js';

const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(currentDirectory, '..');

const config = loadServerConfig();
const privateFilesDirectory = path.resolve(projectDirectory, config.PRIVATE_FILES_DIR);
const pool = createPool(config);
const fedapay = config.FEDAPAY_SECRET_KEY
  ? createFedaPayClient({
      secretKey: config.FEDAPAY_SECRET_KEY,
      environment: config.FEDAPAY_ENVIRONMENT,
      callbackUrl: config.FEDAPAY_CALLBACK_URL,
    })
  : null;
console.info(
  `FedaPay sandbox ${fedapay ? 'configuré' : 'non configuré (clé absente)'}.`,
);
const app = createApp({
  pool,
  jwtSecret: config.JWT_SECRET,
  corsOrigins: config.corsOrigins,
  privateFilesDirectory,
  fedapay,
  fedapayEnvironment: config.FEDAPAY_ENVIRONMENT,
  mailApiKey: config.MAIL_API_KEY,
  mailFromEmail: config.MAIL_FROM_EMAIL ?? '',
  mailFromName: config.MAIL_FROM_NAME,
  publicApiUrl: config.publicApiUrl,
});
const server = app.listen(config.PORT, config.HOST, () => {
  console.info(`API démarrée sur le port ${config.PORT}.`);
});

function shutdown(signal) {
  console.info(`Arrêt demandé (${signal}).`);
  server.close((serverError) => {
    pool.end().then(
      () => {
        if (serverError) {
          console.error(`Échec de l’arrêt HTTP : ${serverError.message}`);
          process.exitCode = 1;
        }
      },
      (databaseError) => {
        console.error(`Échec de fermeture MySQL : ${databaseError.message}`);
        process.exitCode = 1;
      },
    );
  });
}

process.once('SIGINT', () => shutdown('SIGINT'));
process.once('SIGTERM', () => shutdown('SIGTERM'));
