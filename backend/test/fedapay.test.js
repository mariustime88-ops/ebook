import assert from 'node:assert/strict';
import test from 'node:test';
import { createFedaPayClient } from '../src/payments/fedapay.js';
import { loadDatabaseConfig, loadServerConfig } from '../src/config.js';

test('FedaPay sandbox creates a test transaction and returns a secure checkout URL', async () => {
  const requests = [];
  const client = createFedaPayClient({
    secretKey: 'sk_sandbox_test-secret',
    environment: 'sandbox',
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return {
        ok: true,
        status: 200,
        json: async () => requests.length === 1
          ? { 'v1/transaction': { id: 42 } }
          : { url: 'https://checkout.fedapay.com/session' },
      };
    },
  });

  const checkout = await client.createCheckout({
    orderId: 7,
    amount: 1250,
    currency: 'XOF',
    description: 'Livre de test',
    callbackUrl: 'https://api.example.test/api/payments/return?orderId=7',
    customer: { email: 'lecteur@example.test' },
  });

  assert.deepEqual(checkout, {
    transactionId: '42',
    paymentUrl: 'https://checkout.fedapay.com/session',
  });
  assert.equal(requests[0].url, 'https://sandbox-api.fedapay.com/v1/transactions');
  assert.match(requests[0].options.headers.Authorization, /^Bearer sk_sandbox_/);
  const body = JSON.parse(requests[0].options.body);
  assert.equal(
    body.callback_url,
    'https://api.example.test/api/payments/return?orderId=7',
  );
  assert.equal(body.mode, undefined);
  assert.deepEqual(body.custom_metadata, { order_id: 7 });
  assert.equal(requests[1].url, 'https://sandbox-api.fedapay.com/v1/transactions/42/token');
});

test('FedaPay rejects non-HTTPS checkout links', async () => {
  const client = createFedaPayClient({
    secretKey: 'sk_sandbox_test-secret',
    fetchImpl: async (_url, options) => ({
      ok: true,
      status: 200,
      json: async () => options.method === 'POST'
        ? { transaction: { id: 42 } }
        : { url: 'javascript:alert(1)' },
    }),
  });

  await assert.rejects(
    client.createCheckout({
      orderId: 7,
      amount: 1250,
      currency: 'XOF',
      description: 'Livre de test',
      customer: {},
    }),
    /lien de paiement HTTPS valide/,
  );
});

test('FedaPay resolves the currency ID returned by its transaction API', async () => {
  const requests = [];
  const client = createFedaPayClient({
    secretKey: 'sk_sandbox_test-secret',
    fetchImpl: async (url) => {
      requests.push(url);
      const payload = url.endsWith('/transactions/42')
        ? { transaction: { id: 42, amount: 1250, status: 'approved', currency_id: 1 } }
        : { currency: { id: 1, iso: 'XOF' } };
      return { ok: true, status: 200, json: async () => payload };
    },
  });

  const transaction = await client.getTransaction(42);

  assert.deepEqual(transaction.currency, { id: 1, iso: 'XOF' });
  assert.deepEqual(requests, [
    'https://sandbox-api.fedapay.com/v1/transactions/42',
    'https://sandbox-api.fedapay.com/v1/currencies/1',
  ]);
});

test('FedaPay refuses live mode to prevent real charges during sandbox testing', () => {
  assert.throws(
    () => createFedaPayClient({
      secretKey: 'sk_sandbox_test-secret',
      environment: 'live',
    }),
    /Environnement FedaPay invalide/,
  );
});

test('blank optional FedaPay environment variables do not prevent API startup', () => {
  const config = loadServerConfig({
    MYSQL_USER: 'test',
    MYSQL_PASSWORD: '',
    JWT_SECRET: 'test-secret-with-more-than-thirty-two-characters',
    FEDAPAY_SECRET_KEY: '',
    FEDAPAY_CALLBACK_URL: '',
  });

  assert.equal(config.FEDAPAY_SECRET_KEY, undefined);
  assert.equal(config.FEDAPAY_CALLBACK_URL, undefined);
  assert.equal(config.FEDAPAY_ENVIRONMENT, 'sandbox');
  assert.throws(
    () => loadServerConfig({
      MYSQL_USER: 'test',
      JWT_SECRET: 'test-secret-with-more-than-thirty-two-characters',
      FEDAPAY_SECRET_KEY: 'sk_live_test-secret',
    }),
    /FEDAPAY_SECRET_KEY doit être une clé secrète sandbox/,
  );
  assert.throws(
    () => loadServerConfig({
      MYSQL_USER: 'test',
      JWT_SECRET: 'test-secret-with-more-than-thirty-two-characters',
      FEDAPAY_ENVIRONMENT: 'live',
    }),
    /FEDAPAY_ENVIRONMENT/,
  );
});

test('database TLS is disabled locally by default and can be enabled for TiDB', () => {
  assert.equal(loadDatabaseConfig({ MYSQL_USER: 'test' }).MYSQL_SSL, false);
  assert.equal(
    loadDatabaseConfig({ MYSQL_USER: 'test', MYSQL_SSL: 'true' }).MYSQL_SSL,
    true,
  );
});
