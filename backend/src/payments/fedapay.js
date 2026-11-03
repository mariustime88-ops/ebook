const environments = {
  sandbox: 'https://sandbox-api.fedapay.com/v1',
};

function resourceFrom(payload, resourceName) {
  return payload?.[`v1/${resourceName}`]
    ?? payload?.[resourceName]
    ?? payload?.data?.[resourceName]
    ?? payload?.data
    ?? payload;
}

export function createFedaPayClient({
  secretKey,
  environment = 'sandbox',
  callbackUrl,
  fetchImpl = fetch,
}) {
  const apiBase = environments[environment];
  if (!apiBase) throw new TypeError('Environnement FedaPay invalide.');
  if (typeof secretKey !== 'string' || secretKey.length === 0) {
    throw new TypeError('La clé secrète FedaPay est obligatoire.');
  }

  const currencyCache = new Map();

  async function request(resourcePath, options = {}) {
    let response;
    try {
      response = await fetchImpl(`${apiBase}${resourcePath}`, {
        ...options,
        signal: AbortSignal.timeout(15000),
        headers: {
          Authorization: `Bearer ${secretKey}`,
          Accept: 'application/json',
          ...(options.body ? { 'Content-Type': 'application/json' } : {}),
          ...options.headers,
        },
      });
    } catch {
      throw new Error('Le service de paiement FedaPay est injoignable.');
    }

    let payload;
    try {
      payload = await response.json();
    } catch {
      throw new Error('Réponse invalide du service de paiement FedaPay.');
    }
    if (!response.ok) {
      throw new Error(`Le service de paiement FedaPay a répondu ${response.status}.`);
    }
    return payload;
  }

  async function getCurrency(currencyId) {
    const id = Number(currencyId);
    if (!Number.isSafeInteger(id) || id < 1) {
      throw new Error('FedaPay n’a pas retourné une devise valide.');
    }

    let currencyPromise = currencyCache.get(id);
    if (!currencyPromise) {
      currencyPromise = request(`/currencies/${id}`)
        .then((payload) => {
          const currency = resourceFrom(payload, 'currency');
          if (typeof currency?.iso !== 'string') {
            throw new Error('FedaPay n’a pas retourné le code de devise.');
          }
          return currency;
        })
        .catch((error) => {
          currencyCache.delete(id);
          throw error;
        });
      currencyCache.set(id, currencyPromise);
    }
    return currencyPromise;
  }

  async function createPaymentUrl(transactionId) {
    const tokenPayload = await request(
      `/transactions/${encodeURIComponent(transactionId)}/token`,
      { method: 'POST' },
    );
    const token = resourceFrom(tokenPayload, 'token');
    const paymentUrl = token?.url ?? tokenPayload?.url;
    if (
      typeof paymentUrl !== 'string'
      || new URL(paymentUrl).protocol !== 'https:'
    ) {
      throw new Error('FedaPay n’a pas retourné de lien de paiement HTTPS valide.');
    }
    return paymentUrl;
  }

  return {
    async createCheckout({
      orderId,
      amount,
      currency,
      description,
      customer,
      callbackUrl: checkoutCallbackUrl,
    }) {
      const transactionPayload = await request('/transactions', {
        method: 'POST',
        body: JSON.stringify({
          description,
          amount,
          currency: { iso: currency },
          ...(
            checkoutCallbackUrl || callbackUrl
              ? { callback_url: checkoutCallbackUrl || callbackUrl }
              : {}
          ),
          custom_metadata: { order_id: orderId },
          customer,
        }),
      });
      const transaction = resourceFrom(transactionPayload, 'transaction');
      if (!transaction?.id) {
        throw new Error('FedaPay n’a pas retourné de transaction valide.');
      }

      return {
        transactionId: String(transaction.id),
        paymentUrl: await createPaymentUrl(transaction.id),
      };
    },

    createPaymentUrl,

    async getTransaction(transactionId) {
      const payload = await request(
        `/transactions/${encodeURIComponent(transactionId)}`,
      );
      const transaction = resourceFrom(payload, 'transaction');
      if (!transaction?.id) {
        throw new Error('FedaPay n’a pas retourné la transaction demandée.');
      }
      if (transaction.currency || transaction.currency_id === undefined) {
        return transaction;
      }
      return {
        ...transaction,
        currency: await getCurrency(transaction.currency_id),
      };
    },
  };
}
