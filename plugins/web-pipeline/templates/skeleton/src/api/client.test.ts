import { ApiError, apiGet, apiPost } from './client';

function respond(status: number, body?: unknown, contentType = 'application/json'): Response {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': contentType },
  });
}

describe('api client', () => {
  const fetchMock = vi.fn<typeof fetch>();
  beforeEach(() => {
    vi.stubGlobal('fetch', fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    fetchMock.mockReset();
  });

  it('gets JSON from the API base path', async () => {
    fetchMock.mockResolvedValue(respond(200, { name: 'a' }));
    await expect(apiGet<{ name: string }>('/things/1')).resolves.toEqual({ name: 'a' });
    const [url, init] = fetchMock.mock.calls[0] ?? [];
    expect(url).toBe('/api/things/1');
    expect(init?.method).toBe('GET');
    expect(new Headers(init?.headers).get('Accept')).toBe('application/json');
  });

  it('passes an abort signal on', async () => {
    fetchMock.mockResolvedValue(respond(200, {}));
    const controller = new AbortController();
    await apiGet('/things', controller.signal);
    expect(fetchMock.mock.calls[0]?.[1]?.signal).toBe(controller.signal);
  });

  it('posts JSON with the headers it was given', async () => {
    fetchMock.mockResolvedValue(respond(201, { id: '1' }));
    await expect(apiPost<{ id: string }>('/things', { name: 'a' }, { 'Idempotency-Key': 'k' })).resolves.toEqual({
      id: '1',
    });
    const init = fetchMock.mock.calls[0]?.[1];
    expect(init?.body).toBe('{"name":"a"}');
    const headers = new Headers(init?.headers);
    expect(headers.get('Content-Type')).toBe('application/json');
    expect(headers.get('Idempotency-Key')).toBe('k');
  });

  it('returns nothing for 204', async () => {
    fetchMock.mockResolvedValue(respond(204));
    await expect(apiPost('/things/1/close', {})).resolves.toBeUndefined();
  });

  it("turns a problem document into an ApiError with the problem's title and error id", async () => {
    fetchMock.mockResolvedValue(
      respond(422, { title: 'Insufficient funds', detail: 'account 123', errorId: 'e-1' }, 'application/problem+json'),
    );
    const error = await apiGet('/things').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 422, message: 'Insufficient funds', errorId: 'e-1' });
    expect(String((error as ApiError).message)).not.toContain('account 123');
  });

  it('gives a plain message when the error has no usable body', async () => {
    fetchMock.mockResolvedValue(new Response('<html>bad gateway</html>', { status: 502 }));
    await expect(apiGet('/things')).rejects.toMatchObject({ status: 502, message: 'Request failed (502)' });
    fetchMock.mockResolvedValue(respond(500, 'just a string'));
    await expect(apiGet('/things')).rejects.toMatchObject({ status: 500, message: 'Request failed (500)' });
  });

  it('says the service could not be reached when the request itself fails', async () => {
    fetchMock.mockRejectedValue(new TypeError('network down'));
    await expect(apiGet('/things')).rejects.toMatchObject({ status: 0, message: 'The service could not be reached' });
  });
});
