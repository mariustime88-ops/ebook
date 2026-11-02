import { randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import {
  mkdir,
  open,
  rename,
  rm,
} from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import bcrypt from 'bcryptjs';
import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import multer from 'multer';
import yauzl from 'yauzl';
import { z } from 'zod';
import { authenticate, requireRole, signAccessToken } from './auth.js';
import { HttpError, errorHandler, notFoundHandler } from './errors.js';

const openZip = promisify(yauzl.open);
const MAX_FILE_SIZE = 25 * 1024 * 1024;
const registerSchema = z.object({
  email: z.string().trim().email().max(191).transform((value) => value.toLowerCase()),
  displayName: z.string().trim().min(2).max(120),
  password: z.string().min(8).max(128),
  accountType: z.enum(['reader', 'author']),
});

const loginSchema = z.object({
  email: z.string().trim().email().max(191).transform((value) => value.toLowerCase()),
  password: z.string().min(1).max(128),
});

const bookSchema = z.object({
  title: z.string().trim().min(2).max(200),
  description: z.string().trim().min(10).max(10000),
  price: z.coerce.number().int().min(1).max(9999999999),
  currency: z.literal('XOF'),
});

const reviewSchema = z.object({
  status: z.enum(['approved', 'rejected']),
  reviewNote: z.string().trim().max(1000).optional().default(''),
}).refine(
  (value) => value.status !== 'rejected' || value.reviewNote.length >= 5,
  { path: ['reviewNote'], message: 'Précisez le motif du refus.' },
);

const userStatusSchema = z.object({
  status: z.enum(['active', 'suspended']),
});

const commissionSchema = z.object({
  percent: z.number().finite().min(0).max(100),
});

function publicUser(user) {
  return {
    id: user.id,
    email: user.email,
    displayName: user.display_name,
    role: user.role,
    status: user.status,
  };
}

function parsePage(query) {
  const parsed = z.object({
    page: z.coerce.number().int().min(1).max(100000).default(1),
    limit: z.coerce.number().int().min(1).max(50).default(20),
    search: z.string().trim().max(100).default(''),
  }).parse(query);
  return {
    ...parsed,
    offset: (parsed.page - 1) * parsed.limit,
  };
}

function fileExtension(fileType) {
  return fileType === 'pdf' ? '.pdf' : '.docx';
}

async function removeIfExists(filePath) {
  try {
    await rm(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

async function isDocxFile(filePath) {
  const archive = await openZip(filePath, {
    lazyEntries: true,
    autoClose: true,
    validateEntrySizes: true,
  });

  return new Promise((resolve, reject) => {
    let entries = 0;
    let hasDocument = false;
    let hasContentTypes = false;
    let settled = false;

    const finish = (result) => {
      if (settled) return;
      settled = true;
      resolve(result);
    };

    archive.on('error', (error) => {
      if (!settled) {
        settled = true;
        reject(error);
      }
    });
    archive.on('entry', (entry) => {
      entries += 1;
      if (entries > 10000) {
        archive.close();
        finish(false);
        return;
      }
      if (entry.fileName === 'word/document.xml') hasDocument = true;
      if (entry.fileName === '[Content_Types].xml') hasContentTypes = true;
      if (hasDocument && hasContentTypes) {
        archive.close();
        finish(true);
        return;
      }
      archive.readEntry();
    });
    archive.on('end', () => finish(hasDocument && hasContentTypes));
    archive.readEntry();
  });
}

async function identifyDocument(filePath) {
  const handle = await open(filePath, 'r');
  const signature = Buffer.alloc(8);
  let bytesRead;
  try {
    ({ bytesRead } = await handle.read(signature, 0, signature.length, 0));
  } finally {
    await handle.close();
  }

  if (bytesRead >= 5 && signature.subarray(0, 5).toString('ascii') === '%PDF-') {
    return 'pdf';
  }
  if (
    bytesRead >= 4 &&
    signature[0] === 0x50 &&
    signature[1] === 0x4b &&
    signature[2] === 0x03 &&
    signature[3] === 0x04 &&
    await isDocxFile(filePath)
  ) {
    return 'docx';
  }
  return null;
}

function createUploadMiddleware(stagingDirectory) {
  const storage = multer.diskStorage({
    destination: (_request, _file, callback) => callback(null, stagingDirectory),
    filename: (_request, _file, callback) => callback(null, `${randomUUID()}.upload`),
  });

  return multer({
    storage,
    limits: { fileSize: MAX_FILE_SIZE, files: 1, fields: 10 },
  }).single('file');
}

export function createApiRouter({
  pool,
  jwtSecret,
  privateFilesDirectory,
  fedapay = null,
  fedapayEnvironment = 'sandbox',
}) {
  const router = express.Router();
  const auth = authenticate(pool, jwtSecret);
  const uploadsDirectory = path.join(privateFilesDirectory, 'books');
  const stagingDirectory = path.join(privateFilesDirectory, '.incoming');
  const upload = createUploadMiddleware(stagingDirectory);
  const paymentLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 20,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
  });

  router.get('/health/live', (_request, response) => {
    response.json({ status: 'ok' });
  });

  router.get('/health/ready', async (_request, response) => {
    await pool.execute('SELECT 1');
    response.json({ status: 'ready' });
  });

  const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 10,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    message: {
      error: 'RATE_LIMITED',
      message: 'Trop de tentatives. Réessayez plus tard.',
    },
  });
  const uploadLimiter = rateLimit({
    windowMs: 60 * 60 * 1000,
    limit: 10,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    message: {
      error: 'RATE_LIMITED',
      message: 'Trop de dépôts. Réessayez plus tard.',
    },
  });

  router.post('/auth/register', authLimiter, async (request, response) => {
    const input = registerSchema.parse(request.body);
    const passwordHash = await bcrypt.hash(input.password, 12);
    const status = input.accountType === 'author' ? 'pending' : 'active';

    try {
      const [result] = await pool.execute(
        `INSERT INTO platform_users
          (email, password_hash, display_name, role, status)
         VALUES (?, ?, ?, ?, ?)`,
        [input.email, passwordHash, input.displayName, input.accountType, status],
      );
      response.status(201).json({
        user: publicUser({
          id: result.insertId,
          email: input.email,
          display_name: input.displayName,
          role: input.accountType,
          status,
        }),
        message: status === 'pending'
          ? 'Votre demande de compte auteur est en attente de validation.'
          : 'Votre compte lecteur est créé.',
      });
    } catch (error) {
      if (error.code === 'ER_DUP_ENTRY') {
        throw new HttpError(409, 'EMAIL_ALREADY_USED', 'Cette adresse e-mail est déjà utilisée.');
      }
      throw error;
    }
  });

  router.post('/auth/login', authLimiter, async (request, response) => {
    const input = loginSchema.parse(request.body);
    const [users] = await pool.execute(
      `SELECT id, email, password_hash, display_name, role, status
       FROM platform_users WHERE email = ? LIMIT 1`,
      [input.email],
    );
    const user = users[0];
    const passwordMatches = user
      ? await bcrypt.compare(input.password, user.password_hash)
      : false;
    if (!user || !passwordMatches) {
      throw new HttpError(401, 'INVALID_CREDENTIALS', 'E-mail ou mot de passe invalide.');
    }
    if (user.status === 'pending') {
      throw new HttpError(403, 'ACCOUNT_PENDING', 'Votre compte attend la validation de l’administrateur.');
    }
    if (user.status !== 'active') {
      throw new HttpError(403, 'ACCOUNT_SUSPENDED', 'Ce compte est suspendu.');
    }

    response.json({
      token: signAccessToken(user.id, jwtSecret),
      user: publicUser(user),
    });
  });

  router.get('/auth/me', auth, (request, response) => {
    response.json({ user: publicUser(request.user) });
  });

  router.get('/books', async (request, response) => {
    const { page, limit, search, offset } = parsePage(request.query);
    const searchTerm = `%${search}%`;
    const [rows, countRows] = await Promise.all([
      pool.execute(
        `SELECT b.id, b.title, b.description, b.price_amount, b.currency,
                b.file_type, b.created_at, u.display_name AS author_name
         FROM platform_books b
         JOIN platform_users u ON u.id = b.author_id
         WHERE b.status = 'approved'
           AND (? = '' OR b.title LIKE ? OR u.display_name LIKE ?)
         ORDER BY b.created_at DESC
         LIMIT ? OFFSET ?`,
        [search, searchTerm, searchTerm, limit, offset],
      ),
      pool.execute(
        `SELECT COUNT(*) AS total
         FROM platform_books b
         JOIN platform_users u ON u.id = b.author_id
         WHERE b.status = 'approved'
           AND (? = '' OR b.title LIKE ? OR u.display_name LIKE ?)`,
        [search, searchTerm, searchTerm],
      ),
    ]);

    response.json({
      books: rows[0],
      page,
      limit,
      total: Number(countRows[0][0].total),
    });
  });

  router.post(
      '/payments/checkout',
      auth,
      requireRole('reader', 'author'),
      paymentLimiter,
      async (request, response) => {
        const { bookId } = z.object({
          bookId: z.coerce.number().int().positive(),
        }).parse(request.body);

        const [existingOrders] = await pool.execute(
          `SELECT id, status, provider_reference FROM platform_orders
           WHERE buyer_id = ? AND book_id = ?
             AND status IN ('paid', 'pending_payment')
           ORDER BY id DESC LIMIT 1`,
          [request.user.id, bookId],
        );
        if (existingOrders[0]?.status === 'paid') {
          response.json({
            orderId: existingOrders[0].id,
            alreadyPaid: true,
          });
          return;
        }
        if (existingOrders[0]?.status === 'pending_payment') {
          if (!fedapay || !existingOrders[0].provider_reference) {
            throw new HttpError(
              503,
              'PAYMENT_NOT_CONFIGURED',
              'La commande existe déjà, mais son lien de paiement ne peut pas être récupéré.',
            );
          }
          try {
            const paymentUrl = await fedapay.createPaymentUrl(
              existingOrders[0].provider_reference,
            );
            response.json({
              orderId: existingOrders[0].id,
              alreadyPaid: false,
              paymentUrl,
              currency: 'XOF',
              environment: fedapayEnvironment,
            });
          } catch (error) {
            console.error(`Échec de récupération du paiement FedaPay : ${error.message}`);
            throw new HttpError(
              502,
              'PAYMENT_PROVIDER_ERROR',
              'FedaPay n’a pas pu réouvrir le paiement. Réessayez plus tard.',
            );
          }
          return;
        }

        if (!fedapay) {
          throw new HttpError(
            503,
            'PAYMENT_NOT_CONFIGURED',
            'Le paiement FedaPay n’est pas encore configuré sur le serveur.',
          );
        }

        const [books] = await pool.execute(
          `SELECT b.id, b.title, b.price_amount, b.currency,
                  b.author_id, u.display_name AS author_name
           FROM platform_books b
           JOIN platform_users u ON u.id = b.author_id
           WHERE b.id = ? AND b.status = 'approved'
           LIMIT 1`,
          [bookId],
        );
        const book = books[0];
        if (!book) {
          throw new HttpError(404, 'BOOK_NOT_FOUND', 'Ce livre n’est pas disponible.');
        }
        if (String(book.author_id) === String(request.user.id)) {
          throw new HttpError(403, 'OWN_BOOK', 'Vous ne pouvez pas acheter votre propre livre.');
        }
        const amount = Number(book.price_amount);
        if (
          book.currency !== 'XOF'
          || !Number.isSafeInteger(amount)
          || amount < 1
        ) {
          throw new HttpError(
            400,
            'UNSUPPORTED_BOOK_PRICE',
            'Le paiement FedaPay nécessite un prix entier en XOF supérieur à zéro.',
          );
        }

        const [settings] = await pool.execute(
          `SELECT setting_value FROM platform_settings
           WHERE setting_key = 'commission_percent' LIMIT 1`,
        );
        const commissionPercent = settings[0]?.setting_value == null
          ? 0
          : Number(settings[0].setting_value);
        if (!Number.isFinite(commissionPercent)) {
          throw new HttpError(
            500,
            'INVALID_COMMISSION',
            'La commission configurée est invalide.',
          );
        }
        const platformFee = Math.round(amount * commissionPercent / 100);
        const sellerPayout = amount - platformFee;

        const [insertResult] = await pool.execute(
          `INSERT INTO platform_orders
            (buyer_id, book_id, amount, platform_fee, seller_payout,
             commission_percent, currency, payment_provider, status)
           VALUES (?, ?, ?, ?, ?, ?, 'XOF', 'FedaPay', 'pending_payment')`,
          [
            request.user.id,
            bookId,
            amount,
            platformFee,
            sellerPayout,
            commissionPercent.toFixed(2),
          ],
        );
        const orderId = insertResult.insertId;
        let checkout;
        try {
          const [firstName, ...lastNameParts] = request.user.display_name.trim().split(/\s+/);
          checkout = await fedapay.createCheckout({
            orderId,
            amount,
            currency: 'XOF',
            description: `Achat du livre : ${book.title}`,
            customer: {
              email: request.user.email,
              firstname: firstName,
              lastname: lastNameParts.join(' ') || firstName,
            },
          });
        } catch (error) {
          await pool.execute(
            `UPDATE platform_orders SET status = 'failed'
             WHERE id = ? AND status = 'pending_payment'`,
            [orderId],
          );
          console.error(`Échec de création du paiement FedaPay : ${error.message}`);
          throw new HttpError(
            502,
            'PAYMENT_PROVIDER_ERROR',
            'FedaPay n’a pas pu créer le paiement. Réessayez plus tard.',
          );
        }

        await pool.execute(
          `UPDATE platform_orders
           SET provider_reference = ?
           WHERE id = ? AND status = 'pending_payment'`,
          [checkout.transactionId, orderId],
        );
        response.status(201).json({
          orderId,
          alreadyPaid: false,
          paymentUrl: checkout.paymentUrl,
          amount,
          currency: 'XOF',
          environment: fedapayEnvironment,
        });
      },
  );

  router.get(
      '/payments/orders/:id',
      auth,
      requireRole('reader', 'author'),
      paymentLimiter,
      async (request, response) => {
        const id = z.coerce.number().int().positive().parse(request.params.id);
        const [orders] = await pool.execute(
          `SELECT id, book_id, amount, currency, status, provider_reference
           FROM platform_orders WHERE id = ? AND buyer_id = ? LIMIT 1`,
          [id, request.user.id],
        );
        const order = orders[0];
        if (!order) {
          throw new HttpError(404, 'ORDER_NOT_FOUND', 'Commande introuvable.');
        }
        if (order.status === 'paid') {
          response.json({ orderId: order.id, bookId: order.book_id, paid: true });
          return;
        }
        if (order.status !== 'pending_payment' || !order.provider_reference) {
          response.json({ orderId: order.id, bookId: order.book_id, paid: false });
          return;
        }
        if (!fedapay) {
          throw new HttpError(
            503,
            'PAYMENT_NOT_CONFIGURED',
            'La vérification FedaPay n’est pas configurée sur le serveur.',
          );
        }

        let transaction;
        try {
          transaction = await fedapay.getTransaction(order.provider_reference);
        } catch (error) {
          console.error(`Échec de vérification du paiement FedaPay : ${error.message}`);
          throw new HttpError(
            502,
            'PAYMENT_VERIFICATION_FAILED',
            'Impossible de vérifier le paiement auprès de FedaPay.',
          );
        }

        const transactionCurrency = typeof transaction.currency === 'string'
          ? transaction.currency
          : transaction.currency?.iso;
        const metadataOrderId = transaction.custom_metadata?.order_id
          ?? transaction.metadata?.order_id;
        const isMatchingPayment = String(transaction.id) === String(order.provider_reference)
          && Number(transaction.amount) === Number(order.amount)
          && transactionCurrency === order.currency
          && (
            metadataOrderId === undefined
            || String(metadataOrderId) === String(order.id)
          );
        if (transaction.status === 'approved' && isMatchingPayment) {
          await pool.execute(
            `UPDATE platform_orders
             SET status = 'paid', paid_at = CURRENT_TIMESTAMP
             WHERE id = ? AND buyer_id = ? AND status = 'pending_payment'`,
            [id, request.user.id],
          );
          const [updatedOrders] = await pool.execute(
            `SELECT id, book_id, status FROM platform_orders
             WHERE id = ? AND buyer_id = ? LIMIT 1`,
            [id, request.user.id],
          );
          response.json({
            orderId: updatedOrders[0].id,
            bookId: updatedOrders[0].book_id,
            paid: updatedOrders[0].status === 'paid',
          });
          return;
        }
        if (
          transaction.status === 'declined'
          || transaction.status === 'canceled'
          || transaction.status === 'cancelled'
        ) {
          await pool.execute(
            `UPDATE platform_orders SET status = 'failed'
             WHERE id = ? AND buyer_id = ? AND status = 'pending_payment'`,
            [id, request.user.id],
          );
        }
        response.json({ orderId: order.id, bookId: order.book_id, paid: false });
      },
  );

  router.get(
      '/purchases/:bookId/file',
      auth,
      requireRole('reader', 'author'),
      async (request, response) => {
        const bookId = z.coerce.number().int().positive().parse(request.params.bookId);
        const [books] = await pool.execute(
          `SELECT b.storage_key, b.file_type, b.original_file_name
           FROM platform_orders o
           JOIN platform_books b ON b.id = o.book_id
           WHERE o.buyer_id = ? AND o.book_id = ? AND o.status = 'paid'
           LIMIT 1`,
          [request.user.id, bookId],
        );
        const book = books[0];
        if (!book) {
          throw new HttpError(
            403,
            'PURCHASE_REQUIRED',
            'Achetez ce livre avant de le télécharger.',
          );
        }

        const filePath = path.join(
          uploadsDirectory,
          `${book.storage_key}${fileExtension(book.file_type)}`,
        );
        response.set({
          'Content-Disposition': `attachment; filename="${path.basename(book.original_file_name).replace(/["\\\\\\r\\n]/g, '_')}"`,
          'X-Content-Type-Options': 'nosniff',
        });
        const file = createReadStream(filePath);
        file.on('error', (error) => {
          if (!response.headersSent) {
            response.status(404).json({
              error: 'FILE_NOT_FOUND',
              message: 'Le fichier acheté est indisponible.',
            });
          } else {
            response.destroy(error);
          }
        });
        file.pipe(response);
      },
  );

  router.get('/author/books', auth, requireRole('author'), async (request, response) => {
    const [books] = await pool.execute(
      `SELECT id, title, description, price_amount, currency, file_type,
              status, review_note, created_at, reviewed_at
       FROM platform_books WHERE author_id = ? ORDER BY created_at DESC`,
      [request.user.id],
    );
    response.json({ books });
  });

  router.post(
    '/author/books',
    auth,
    requireRole('author'),
    uploadLimiter,
    (request, response, next) => {
      mkdir(stagingDirectory, { recursive: true }).then(
        () => upload(request, response, next),
        next,
      );
    },
    async (request, response) => {
      if (!request.file) {
        throw new HttpError(400, 'FILE_REQUIRED', 'Joignez un fichier PDF ou DOCX.');
      }

      let permanentPath;
      try {
        const documentType = await identifyDocument(request.file.path);
        if (!documentType) {
          throw new HttpError(
            400,
            'UNSUPPORTED_FILE',
            'Le fichier doit être un document PDF ou DOCX valide.',
          );
        }

        const input = bookSchema.parse(request.body);
        const storageKey = randomUUID();
        await mkdir(uploadsDirectory, { recursive: true });
        permanentPath = path.join(uploadsDirectory, `${storageKey}${fileExtension(documentType)}`);
        await rename(request.file.path, permanentPath);

        const [result] = await pool.execute(
          `INSERT INTO platform_books
            (author_id, title, description, price_amount, currency, storage_key,
             original_file_name, file_type, file_size_bytes, status)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
          [
            request.user.id,
            input.title,
            input.description,
            input.price.toFixed(2),
            input.currency,
            storageKey,
            path.basename(request.file.originalname).replace(/[\\/]/g, '').slice(0, 255),
            documentType,
            request.file.size,
          ],
        );
        permanentPath = undefined;

        response.status(201).json({
          book: {
            id: result.insertId,
            title: input.title,
            price: input.price.toFixed(2),
            currency: input.currency,
            fileType: documentType,
            status: 'pending',
          },
          message: 'Votre livre a été envoyé à l’administrateur pour validation.',
        });
      } finally {
        await removeIfExists(request.file.path);
        if (permanentPath) await removeIfExists(permanentPath);
      }
    },
  );

  router.get('/admin/users', auth, requireRole('admin'), async (request, response) => {
    const query = z.object({
      status: z.enum(['pending', 'active', 'suspended']).optional(),
      role: z.enum(['reader', 'author', 'admin']).optional(),
    }).parse(request.query);
    const conditions = [];
    const parameters = [];
    if (query.status) {
      conditions.push('status = ?');
      parameters.push(query.status);
    }
    if (query.role) {
      conditions.push('role = ?');
      parameters.push(query.role);
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const [users] = await pool.execute(
      `SELECT id, email, display_name, role, status, created_at
       FROM platform_users ${where}
       ORDER BY created_at DESC LIMIT 200`,
      parameters,
    );
    response.json({ users: users.map(publicUser) });
  });

  router.patch(
    '/admin/users/:id/status',
    auth,
    requireRole('admin'),
    async (request, response) => {
      const id = z.coerce.number().int().positive().parse(request.params.id);
      const { status } = userStatusSchema.parse(request.body);
      const [result] = await pool.execute(
        `UPDATE platform_users SET status = ?
         WHERE id = ? AND role <> 'admin'`,
        [status, id],
      );
      if (result.affectedRows === 0) {
        const [users] = await pool.execute(
          "SELECT id FROM platform_users WHERE id = ? AND role <> 'admin' LIMIT 1",
          [id],
        );
        if (users.length > 0) {
          response.json({ message: 'Statut du compte inchangé.' });
          return;
        }
        throw new HttpError(404, 'USER_NOT_FOUND', 'Utilisateur introuvable.');
      }
      response.json({ message: 'Statut du compte mis à jour.' });
    },
  );

  router.get('/admin/books', auth, requireRole('admin'), async (request, response) => {
    const query = z.object({
      status: z.enum(['pending', 'approved', 'rejected']).default('pending'),
    }).parse(request.query);
    const [books] = await pool.execute(
      `SELECT b.id, b.title, b.description, b.price_amount, b.currency,
              b.file_type, b.original_file_name, b.file_size_bytes, b.status,
              b.review_note, b.created_at, u.id AS author_id,
              u.email AS author_email, u.display_name AS author_name
       FROM platform_books b
       JOIN platform_users u ON u.id = b.author_id
       WHERE b.status = ? ORDER BY b.created_at ASC LIMIT 200`,
      [query.status],
    );
    response.json({ books });
  });

  router.get(
    '/admin/books/:id/file',
    auth,
    requireRole('admin'),
    async (request, response) => {
      const id = z.coerce.number().int().positive().parse(request.params.id);
      const [books] = await pool.execute(
        `SELECT storage_key, file_type, original_file_name
         FROM platform_books WHERE id = ? LIMIT 1`,
        [id],
      );
      const book = books[0];
      if (!book) {
        throw new HttpError(404, 'BOOK_NOT_FOUND', 'Livre introuvable.');
      }

      const filePath = path.join(
        uploadsDirectory,
        `${book.storage_key}${fileExtension(book.file_type)}`,
      );
      response.set({
        'Content-Disposition': `attachment; filename="${path.basename(book.original_file_name).replace(/["\\\r\n]/g, '_')}"`,
        'X-Content-Type-Options': 'nosniff',
      });
      const file = createReadStream(filePath);
      file.on('error', (error) => {
        if (!response.headersSent) {
          response.status(404).json({
            error: 'FILE_NOT_FOUND',
            message: 'Le fichier privé est indisponible.',
          });
        } else {
          response.destroy(error);
        }
      });
      file.pipe(response);
    },
  );

  router.patch(
    '/admin/books/:id/review',
    auth,
    requireRole('admin'),
    async (request, response) => {
      const id = z.coerce.number().int().positive().parse(request.params.id);
      const review = reviewSchema.parse(request.body);
      const [result] = await pool.execute(
        `UPDATE platform_books
         SET status = ?, review_note = ?, reviewed_by = ?, reviewed_at = CURRENT_TIMESTAMP
         WHERE id = ? AND status = 'pending'`,
        [review.status, review.reviewNote || null, request.user.id, id],
      );
      if (result.affectedRows === 0) {
        const [books] = await pool.execute(
          'SELECT id FROM platform_books WHERE id = ? LIMIT 1',
          [id],
        );
        if (books.length === 0) {
          throw new HttpError(404, 'BOOK_NOT_FOUND', 'Livre introuvable.');
        }
        throw new HttpError(409, 'BOOK_ALREADY_REVIEWED', 'Ce livre a déjà été examiné.');
      }
      response.json({ message: 'Décision de modération enregistrée.' });
    },
  );

  router.get(
    '/admin/settings/commission',
    auth,
    requireRole('admin'),
    async (_request, response) => {
      const [settings] = await pool.execute(
        `SELECT setting_value, updated_at
         FROM platform_settings WHERE setting_key = 'commission_percent'`,
      );
      const setting = settings[0];
      response.json({
        configured: setting?.setting_value !== null && setting?.setting_value !== undefined,
        percent: setting?.setting_value === null || setting === undefined
          ? null
          : Number(setting.setting_value),
        updatedAt: setting?.updated_at ?? null,
      });
    },
  );

  router.put(
    '/admin/settings/commission',
    auth,
    requireRole('admin'),
    async (request, response) => {
      const { percent } = commissionSchema.parse(request.body);
      const normalizedPercent = percent.toFixed(2);
      await pool.execute(
        `INSERT INTO platform_settings (setting_key, setting_value, updated_by)
         VALUES ('commission_percent', ?, ?)
         ON DUPLICATE KEY UPDATE
           setting_value = VALUES(setting_value),
           updated_by = VALUES(updated_by)`,
        [normalizedPercent, request.user.id],
      );
      response.json({
        configured: true,
        percent: Number(normalizedPercent),
      });
    },
  );

  router.get(
    '/admin/settings/payment-provider',
    auth,
    requireRole('admin'),
    (_request, response) => {
      response.json({
        provider: 'FedaPay',
        environment: fedapayEnvironment,
        configured: fedapay !== null,
        currency: 'XOF',
        automaticPayouts: false,
      });
    },
  );

  router.get('/admin/dashboard', auth, requireRole('admin'), async (_request, response) => {
    const [users, books, sales, popularBooks] = await Promise.all([
      pool.execute(
        `SELECT role, status, COUNT(*) AS count
         FROM platform_users GROUP BY role, status`,
      ),
      pool.execute(
        `SELECT status, COUNT(*) AS count
         FROM platform_books GROUP BY status`,
      ),
      pool.execute(
        `SELECT currency, COUNT(*) AS paid_orders,
                SUM(amount) AS gross_sales, SUM(platform_fee) AS platform_revenue
         FROM platform_orders WHERE status = 'paid'
         GROUP BY currency ORDER BY currency`,
      ),
      pool.execute(
        `SELECT b.id, b.title, COUNT(o.id) AS sales_count
         FROM platform_books b
         JOIN platform_orders o ON o.book_id = b.id AND o.status = 'paid'
         GROUP BY b.id, b.title ORDER BY sales_count DESC LIMIT 10`,
      ),
    ]);
    response.json({
      users: users[0],
      books: books[0],
      salesByCurrency: sales[0],
      popularBooks: popularBooks[0],
    });
  });

  return router;
}

export function createApp({
  pool,
  jwtSecret,
  corsOrigins = [],
  privateFilesDirectory,
  fedapay = null,
  fedapayEnvironment = 'sandbox',
}) {
  if (!pool || typeof pool.execute !== 'function') {
    throw new TypeError('Une connexion MySQL est obligatoire.');
  }
  if (typeof jwtSecret !== 'string' || jwtSecret.length < 32) {
    throw new TypeError('Un secret JWT d’au moins 32 caractères est obligatoire.');
  }
  if (!privateFilesDirectory) {
    throw new TypeError('Un répertoire privé de stockage est obligatoire.');
  }

  const app = express();
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(cors({
    origin: corsOrigins.length ? corsOrigins : false,
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    maxAge: 600,
  }));
  app.use(express.json({ limit: '32kb' }));
  app.use('/api', createApiRouter({
    pool,
    jwtSecret,
    privateFilesDirectory,
    fedapay,
    fedapayEnvironment,
  }));

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
