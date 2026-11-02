import jwt from 'jsonwebtoken';
import { HttpError } from './errors.js';

const issuer = 'application-livre-api';
const audience = 'application-livre';

export function signAccessToken(userId, secret) {
  return jwt.sign({}, secret, {
    algorithm: 'HS256',
    subject: String(userId),
    issuer,
    audience,
    expiresIn: '1h',
  });
}

export function authenticate(pool, secret) {
  return async (request, _response, next) => {
    try {
      const authorization = request.get('authorization') ?? '';
      const match = /^Bearer ([^\s]+)$/i.exec(authorization);
      if (!match) {
        throw new HttpError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
      }

      let payload;
      try {
        payload = jwt.verify(match[1], secret, {
          algorithms: ['HS256'],
          issuer,
          audience,
        });
      } catch {
        throw new HttpError(401, 'INVALID_TOKEN', 'La session a expiré ou est invalide.');
      }

      const userId = Number(payload.sub);
      if (!Number.isSafeInteger(userId) || userId < 1) {
        throw new HttpError(401, 'INVALID_TOKEN', 'La session a expiré ou est invalide.');
      }

      const [users] = await pool.execute(
        `SELECT id, email, display_name, role, status
         FROM platform_users WHERE id = ? LIMIT 1`,
        [userId],
      );
      const user = users[0];
      if (!user || user.status !== 'active') {
        throw new HttpError(401, 'INVALID_SESSION', 'Cette session n’est plus active.');
      }

      request.user = user;
      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireRole(...roles) {
  return (request, _response, next) => {
    if (!request.user) {
      next(new HttpError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.'));
      return;
    }
    if (!roles.includes(request.user.role)) {
      next(new HttpError(403, 'FORBIDDEN', 'Vous n’avez pas accès à cette action.'));
      return;
    }
    next();
  };
}
