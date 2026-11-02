export class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function notFoundHandler(_request, _response, next) {
  next(new HttpError(404, 'NOT_FOUND', 'Cette ressource est introuvable.'));
}

export function errorHandler(error, _request, response, _next) {
  if (error?.type === 'entity.too.large') {
    response.status(413).json({
      error: 'REQUEST_TOO_LARGE',
      message: 'La requête est trop volumineuse.',
    });
    return;
  }

  if (error?.type === 'entity.parse.failed' || (error instanceof SyntaxError && 'body' in error)) {
    response.status(400).json({
      error: 'INVALID_JSON',
      message: 'Le corps JSON est invalide.',
    });
    return;
  }

  if (error?.name === 'MulterError') {
    const tooLarge = error.code === 'LIMIT_FILE_SIZE';
    response.status(tooLarge ? 413 : 400).json({
      error: tooLarge ? 'FILE_TOO_LARGE' : 'INVALID_UPLOAD',
      message: tooLarge
        ? 'Le fichier dépasse la limite de 25 Mo.'
        : 'Le fichier envoyé est invalide ou trop volumineux.',
    });
    return;
  }

  if (error instanceof HttpError) {
    response.status(error.status).json({
      error: error.code,
      message: error.message,
    });
    return;
  }

  if (error?.name === 'ZodError') {
    response.status(400).json({
      error: 'VALIDATION_ERROR',
      message: 'Certaines informations sont invalides.',
      details: error.issues.map(({ path, message }) => ({
        field: path.join('.'),
        message,
      })),
    });
    return;
  }

  console.error(`Erreur API : ${error?.message ?? 'Erreur inconnue'}`);
  response.status(500).json({
    error: 'INTERNAL_ERROR',
    message: 'Une erreur interne est survenue.',
  });
}
