/**
 * The only way to the backend. Everything else imports from src/api and never calls fetch itself
 * (an ESLint rule and the architecture rules enforce it).
 *
 * The service answers errors as RFC 9457 problem documents; ApiError carries their status and title. A problem's
 * detail may name identifiers: show `title` to people, never log or display the whole document.
 */
const baseUrl: string = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? '/api';

export class ApiError extends Error {
  readonly status: number;
  readonly errorId: string | undefined;

  constructor(status: number, title: string, errorId?: string) {
    super(title);
    this.name = 'ApiError';
    this.status = status;
    this.errorId = errorId;
  }
}

interface Problem {
  title?: unknown;
  errorId?: unknown;
}

async function problemOf(response: Response): Promise<Problem> {
  try {
    const body: unknown = await response.json();
    return typeof body === 'object' && body !== null ? body : {};
  } catch {
    return {};
  }
}

async function request<T>(path: string, init: RequestInit): Promise<T> {
  // Headers, not an object spread: a caller's HeadersInit may be a Headers object or an array of pairs.
  const headers = new Headers(init.headers);
  if (!headers.has('Accept')) headers.set('Accept', 'application/json');
  let response: Response;
  try {
    response = await fetch(`${baseUrl}${path}`, { ...init, headers });
  } catch {
    throw new ApiError(0, 'The service could not be reached');
  }
  if (!response.ok) {
    const problem = await problemOf(response);
    const title =
      typeof problem.title === 'string' ? problem.title : `Request failed (${String(response.status)})`;
    throw new ApiError(
      response.status,
      title,
      typeof problem.errorId === 'string' ? problem.errorId : undefined,
    );
  }
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

export function apiGet<T>(path: string, signal?: AbortSignal): Promise<T> {
  return request<T>(path, signal ? { method: 'GET', signal } : { method: 'GET' });
}

export function apiPost<T>(path: string, body: unknown, headers: Record<string, string> = {}): Promise<T> {
  return request<T>(path, {
    method: 'POST',
    body: JSON.stringify(body),
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}
