import * as Sentry from '@sentry/browser';

const DSN = import.meta.env.VITE_SENTRY_DSN || '';

export function initSentry() {
  if (!DSN) return;
  Sentry.init({
    dsn: DSN,
    environment: import.meta.env.MODE,
    tracesSampleRate: 0.1,
    beforeSend(event) {
      if (event.exception) {
        const frames = event.exception.values?.[0]?.stacktrace?.frames;
        if (frames?.some((f) => f.filename?.includes('extensions/'))) return null;
      }
      return event;
    },
  });
}

export function captureError(error, context) {
  if (!DSN) return;
  Sentry.captureException(error, { extra: context });
}

export function setUser(username, role) {
  if (!DSN) return;
  Sentry.setUser({ username, role });
}
