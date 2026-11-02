import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdir, mkdtemp, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createApp } from '../src/http/routes.js';
import { signAccessToken } from '../src/http/auth.js';

const jwtSecret = 'test-secret-with-more-than-thirty-two-characters';

async function startServer(t, pool, options = {}) {
  const privateFilesDirectory = await mkdtemp(
    path.join(os.tmpdir(), 'application-livre-api-'),
  );
  const server = createApp({
    pool,
    jwtSecret,
    corsOrigins: [
      'http://localhost:5013',
      'http://127.0.0.1:5013',
      'http://localhost:5014',
      'http://127.0.0.1:5014',
    ],
    privateFilesDirectory,
    ...options,
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
    await rm(privateFilesDirectory, { recursive: true, force: true });
  });

  const address = server.address();
  return {
    baseUrl: `http://127.0.0.1:${address.port}/api`,
    privateFilesDirectory,
  };
}

test('allows registration requests from the local Flutter web port 5014', async (t) => {
  const app = await startServer(t, {
    execute: async () => {
      throw new Error('Un précontrôle CORS ne doit pas interroger MySQL.');
    },
  });

  const response = await fetch(`${app.baseUrl}/auth/register`, {
    method: 'OPTIONS',
    headers: {
      Origin: 'http://127.0.0.1:5014',
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers': 'content-type',
    },
  });

  assert.equal(response.status, 204);
  assert.equal(
    response.headers.get('access-control-allow-origin'),
    'http://127.0.0.1:5014',
  );
});

test('health endpoint responds without querying the database', async (t) => {
  const app = await startServer(t, {
    execute: async () => {
      throw new Error('La vérification de disponibilité ne doit pas interroger MySQL.');
    },
  });

  const response = await fetch(`${app.baseUrl}/health/live`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok' });
});

test('author-only routes reject unauthenticated requests', async (t) => {
  const app = await startServer(t, {
    execute: async () => {
      throw new Error('Une requête non authentifiée ne doit pas accéder à MySQL.');
    },
  });

  const response = await fetch(`${app.baseUrl}/author/books`);
  assert.equal(response.status, 401);
  assert.equal((await response.json()).error, 'AUTHENTICATION_REQUIRED');
});

test('legacy non-FedaPay payment destination routes are removed', async (t) => {
  const app = await startServer(t, {
    execute: async () => {
      throw new Error('Removed payment routes must not access the database.');
    },
  });

  for (const route of ['/author/payout-destination', '/admin/settings/payment-destination']) {
    const response = await fetch(`${app.baseUrl}${route}`);
    assert.equal(response.status, 404);
  }
});

test('administration routes reject readers even with a valid token', async (t) => {
  const app = await startServer(t, {
    execute: async (sql) => {
      assert.match(sql, /FROM platform_users WHERE id = \? LIMIT 1/);
      return [[{
        id: 8,
        email: 'reader@example.test',
        display_name: 'Lecteur',
        role: 'reader',
        status: 'active',
      }], []];
    },
  });
  const token = signAccessToken(8, jwtSecret);

  const response = await fetch(`${app.baseUrl}/admin/users`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.equal(response.status, 403);
  assert.equal((await response.json()).error, 'FORBIDDEN');
});

test('book listing only returns approved catalogue entries', async (t) => {
  const app = await startServer(t, {
    execute: async (sql) => {
      assert.match(sql, /b\.status = 'approved'/);
      if (sql.includes('COUNT(*)')) {
        return [[{ total: 1 }], []];
      }
      return [[{
        id: 4,
        title: 'Un livre validé',
        description: 'Un extrait de démonstration.',
        price_amount: '5.00',
        currency: 'XOF',
        file_type: 'pdf',
        author_name: 'Auteur',
      }], []];
    },
  });

  const response = await fetch(`${app.baseUrl}/books`);
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.total, 1);
  assert.equal(result.books[0].title, 'Un livre validé');
});

  test('checkout reports a clear error while FedaPay is not configured', async (t) => {
    const app = await startServer(t, {
      execute: async (sql) => {
        if (sql.includes('FROM platform_users WHERE id = ? LIMIT 1')) {
          return [[{
            id: 9,
            email: 'reader@example.test',
            display_name: 'Lecteur test',
            role: 'reader',
            status: 'active',
          }], []];
        }
        if (sql.includes('FROM platform_orders')) return [[], []];
        throw new Error(`Requête non prévue dans le test : ${sql}`);
      },
    });
    const token = signAccessToken(9, jwtSecret);

    const response = await fetch(`${app.baseUrl}/payments/checkout`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ bookId: 4 }),
    });

    assert.equal(response.status, 503);
    assert.equal((await response.json()).error, 'PAYMENT_NOT_CONFIGURED');
  });

  test('checkout works without author payout details and stores the commission split', async (t) => {
    let insertedOrder;
    let checkoutInput;
    const app = await startServer(t, {
      execute: async (sql, parameters) => {
        if (sql.includes('FROM platform_users WHERE id = ? LIMIT 1')) {
          return [[{
            id: 9,
            email: 'reader@example.test',
            display_name: 'Lecteur test',
            role: 'reader',
            status: 'active',
          }], []];
        }
        if (sql.includes('SELECT id, status, provider_reference FROM platform_orders')) {
          return [[], []];
        }
        if (sql.includes("b.status = 'approved'")) {
          return [[{
            id: 4,
            title: 'Livre validé',
            price_amount: '1000.00',
            currency: 'XOF',
            author_id: 7,
            author_name: 'Auteur test',
          }], []];
        }
        if (sql.includes("setting_key = 'commission_percent'")) {
          return [[{ setting_value: '20.00' }], []];
        }
        if (sql.includes('INSERT INTO platform_orders')) {
          insertedOrder = parameters;
          return [{ insertId: 19 }, []];
        }
        if (sql.includes('SET provider_reference = ?')) {
          assert.deepEqual(parameters, ['transaction-19', 19]);
          return [{ affectedRows: 1 }, []];
        }
        throw new Error(`Requête non prévue dans le test : ${sql}`);
      },
    }, {
      fedapay: {
        createCheckout: async (input) => {
          checkoutInput = input;
          return {
            transactionId: 'transaction-19',
            paymentUrl: 'https://checkout.fedapay.com/test',
          };
        },
        createPaymentUrl: async () => 'https://checkout.fedapay.com/test',
      },
      fedapayEnvironment: 'sandbox',
    });
    const token = signAccessToken(9, jwtSecret);

    const response = await fetch(`${app.baseUrl}/payments/checkout`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ bookId: 4 }),
    });

    assert.equal(response.status, 201);
    assert.deepEqual(await response.json(), {
      orderId: 19,
      alreadyPaid: false,
      paymentUrl: 'https://checkout.fedapay.com/test',
      amount: 1000,
      currency: 'XOF',
      environment: 'sandbox',
    });
    assert.deepEqual(insertedOrder, [9, 4, 1000, 200, 800, '20.00']);
    assert.equal(checkoutInput.orderId, 19);
    assert.equal(checkoutInput.currency, 'XOF');
    assert.equal(checkoutInput.customer.email, 'reader@example.test');
  });

  test('checkout defaults to a zero commission when no rate is configured', async (t) => {
    let insertedOrder;
    const app = await startServer(t, {
      execute: async (sql, parameters) => {
        if (sql.includes('FROM platform_users WHERE id = ? LIMIT 1')) {
          return [[{
            id: 9,
            email: 'reader@example.test',
            display_name: 'Lecteur test',
            role: 'reader',
            status: 'active',
          }], []];
        }
        if (sql.includes('SELECT id, status, provider_reference FROM platform_orders')) {
          return [[], []];
        }
        if (sql.includes("b.status = 'approved'")) {
          return [[{
            id: 4,
            title: 'Livre validé',
            price_amount: '1000.00',
            currency: 'XOF',
            author_id: 7,
            author_name: 'Auteur test',
          }], []];
        }
        if (sql.includes("setting_key = 'commission_percent'")) return [[], []];
        if (sql.includes('INSERT INTO platform_orders')) {
          insertedOrder = parameters;
          return [{ insertId: 20 }, []];
        }
        if (sql.includes('SET provider_reference = ?')) {
          return [{ affectedRows: 1 }, []];
        }
        throw new Error(`Requête non prévue dans le test : ${sql}`);
      },
    }, {
      fedapay: {
        createCheckout: async () => ({
          transactionId: 'transaction-20',
          paymentUrl: 'https://checkout.fedapay.com/test',
        }),
        createPaymentUrl: async () => 'https://checkout.fedapay.com/test',
      },
      fedapayEnvironment: 'sandbox',
    });
    const token = signAccessToken(9, jwtSecret);

    const response = await fetch(`${app.baseUrl}/payments/checkout`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ bookId: 4 }),
    });

    assert.equal(response.status, 201);
    assert.deepEqual(insertedOrder, [9, 4, 1000, 0, 1000, '0.00']);
  });

  test('payment verification only marks a matching approved transaction paid', async (t) => {
    const updates = [];
    const app = await startServer(t, {
      execute: async (sql, parameters) => {
        if (sql.includes('FROM platform_users WHERE id = ? LIMIT 1')) {
          return [[{
            id: 9,
            email: 'reader@example.test',
            display_name: 'Lecteur test',
            role: 'reader',
            status: 'active',
          }], []];
        }
        if (sql.includes('FROM platform_orders WHERE id = ? AND buyer_id = ? LIMIT 1')) {
          return [[{
            id: 19,
            book_id: 4,
            amount: '1000.00',
            currency: 'XOF',
            status: 'pending_payment',
            provider_reference: 'transaction-19',
          }], []];
        }
        if (sql.includes("SET status = 'paid'")) {
          updates.push(parameters);
          return [{ affectedRows: 1 }, []];
        }
        if (sql.includes('SELECT id, book_id, status FROM platform_orders')) {
          return [[{ id: 19, book_id: 4, status: 'paid' }], []];
        }
        throw new Error(`Requête non prévue dans le test : ${sql}`);
      },
    }, {
      fedapay: {
        getTransaction: async () => ({
          id: 'transaction-19',
          status: 'approved',
          amount: 1000,
          currency: { iso: 'XOF' },
          custom_metadata: { order_id: 19 },
        }),
      },
    });
    const token = signAccessToken(9, jwtSecret);

    const response = await fetch(`${app.baseUrl}/payments/orders/19`, {
      headers: { Authorization: `Bearer ${token}` },
    });

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      orderId: 19,
      bookId: 4,
      paid: true,
    });
    assert.deepEqual(updates, [[19, 9]]);
  });

  test('payment verification leaves an approved transaction with a wrong or missing currency unpaid', async (t) => {
    let transactionCurrency;
    const app = await startServer(t, {
      execute: async (sql) => {
        if (sql.includes('FROM platform_users WHERE id = ? LIMIT 1')) {
          return [[{
            id: 9,
            email: 'reader@example.test',
            display_name: 'Lecteur test',
            role: 'reader',
            status: 'active',
          }], []];
        }
        if (sql.includes('FROM platform_orders WHERE id = ? AND buyer_id = ? LIMIT 1')) {
          return [[{
            id: 19,
            book_id: 4,
            amount: '1000.00',
            currency: 'XOF',
            status: 'pending_payment',
            provider_reference: 'transaction-19',
          }], []];
        }
        throw new Error(`Aucune écriture ne doit être effectuée : ${sql}`);
      },
    }, {
      fedapay: {
        getTransaction: async () => ({
          id: 'transaction-19',
          status: 'approved',
          amount: 1000,
          currency: transactionCurrency,
        }),
      },
    });
    const token = signAccessToken(9, jwtSecret);

    for (const currency of [undefined, { iso: 'EUR' }]) {
      transactionCurrency = currency;
      const response = await fetch(`${app.baseUrl}/payments/orders/19`, {
        headers: { Authorization: `Bearer ${token}` },
      });

      assert.equal(response.status, 200);
      assert.equal((await response.json()).paid, false);
    }
  });

test('registration accepts an eight-character password', async (t) => {
  const app = await startServer(t, {
    execute: async (sql, parameters) => {
      assert.match(sql, /INSERT INTO platform_users/);
      assert.equal(parameters[1].startsWith('$2'), true);
      return [{ insertId: 12, affectedRows: 1 }, []];
    },
  });

  const response = await fetch(`${app.baseUrl}/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: 'lecteur@example.test',
      displayName: 'Lecteur test',
      password: 'abC12345',
      accountType: 'reader',
    }),
  });

  assert.equal(response.status, 201);
  assert.equal((await response.json()).user.status, 'active');
});

test('registration rejects a seven-character password', async (t) => {
  const app = await startServer(t, {
    execute: async () => {
      throw new Error('Un mot de passe invalide ne doit pas être enregistré.');
    },
  });

  const response = await fetch(`${app.baseUrl}/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: 'lecteur@example.test',
      displayName: 'Lecteur test',
      password: 'abC1234',
      accountType: 'reader',
    }),
  });

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, 'VALIDATION_ERROR');
});

test('author upload stores a PDF privately and submits it for moderation', async (t) => {
  let insertedBook;
  const app = await startServer(t, {
    execute: async (sql, parameters) => {
      if (sql.includes('FROM platform_users WHERE id = ?')) {
        return [[{
          id: 9,
          email: 'author@example.test',
          display_name: 'Auteur',
          role: 'author',
          status: 'active',
        }], []];
      }
      if (sql.includes('INSERT INTO platform_books')) {
        insertedBook = parameters;
        return [{ insertId: 42, affectedRows: 1 }, []];
      }
      throw new Error(`Requête non prévue dans le test : ${sql}`);
    },
  });

  const token = signAccessToken(9, jwtSecret);
  const form = new FormData();
  form.set('title', 'Livre en attente');
  form.set('description', 'Une description suffisamment longue.');
  form.set('price', '8');
  form.set('currency', 'XOF');
  form.set(
    'file',
    new Blob([Buffer.from('%PDF-1.7\nExtrait de test')], {
      type: 'application/pdf',
    }),
    'livre.pdf',
  );

  const response = await fetch(`${app.baseUrl}/author/books`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  });
  assert.equal(response.status, 201);
  assert.equal((await response.json()).book.status, 'pending');
  assert.equal(insertedBook[6], 'livre.pdf');
  assert.equal(insertedBook[7], 'pdf');

  const privateBooksDirectory = path.join(app.privateFilesDirectory, 'books');
  const files = await readdir(privateBooksDirectory);
  assert.equal(files.length, 1);
  assert.match(files[0], /\.pdf$/);
});

test('upload rejects a renamed non-document without inserting a book', async (t) => {
  let insertedBook = false;
  const app = await startServer(t, {
    execute: async (sql) => {
      if (sql.includes('FROM platform_users WHERE id = ?')) {
        return [[{
          id: 9,
          email: 'author@example.test',
          display_name: 'Auteur',
          role: 'author',
          status: 'active',
        }], []];
      }
      insertedBook = true;
      throw new Error('Un fichier invalide ne doit pas créer un livre.');
    },
  });

  const token = signAccessToken(9, jwtSecret);
  const form = new FormData();
  form.set('title', 'Faux document');
  form.set('description', 'Une description suffisamment longue.');
  form.set('price', '8');
  form.set('currency', 'XOF');
  form.set(
    'file',
    new Blob(['ceci n’est pas un PDF'], { type: 'application/pdf' }),
    'faux.pdf',
  );

  const response = await fetch(`${app.baseUrl}/author/books`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, 'UNSUPPORTED_FILE');
  assert.equal(insertedBook, false);
});

test('only an administrator can retrieve a submitted book for review', async (t) => {
  const app = await startServer(t, {
    execute: async (sql) => {
      if (sql.includes('FROM platform_users WHERE id = ?')) {
        return [[{
          id: 2,
          email: 'admin@example.test',
          display_name: 'Administrateur',
          role: 'admin',
          status: 'active',
        }], []];
      }
      if (sql.includes('SELECT storage_key, file_type, original_file_name')) {
        return [[{
          storage_key: '12345678-1234-1234-1234-123456789012',
          file_type: 'pdf',
          original_file_name: 'document.pdf',
        }], []];
      }
      throw new Error(`Requête non prévue dans le test : ${sql}`);
    },
  });
  const storageKey = '12345678-1234-1234-1234-123456789012';
  const booksDirectory = path.join(app.privateFilesDirectory, 'books');
  await mkdir(booksDirectory, { recursive: true });
  await writeFile(path.join(booksDirectory, `${storageKey}.pdf`), '%PDF-1.7\nreview');

  const token = signAccessToken(2, jwtSecret);
  const response = await fetch(`${app.baseUrl}/admin/books/42/file`, {
    headers: { Authorization: `Bearer ${token}` },
  });

  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-disposition'), /document\.pdf/);
  assert.equal(await response.text(), '%PDF-1.7\nreview');
});
