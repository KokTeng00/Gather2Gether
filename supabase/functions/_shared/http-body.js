export class BodyTooLargeError extends Error {
  constructor() {
    super('request_too_large');
  }
}

// Count bytes while reading. Content-Length is only an early rejection hint:
// chunked requests and dishonest clients must have the same memory ceiling.
export async function readBoundedText(message, maximumBytes) {
  const declaredLength = Number(message.headers.get('Content-Length') ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    await message.body?.cancel().catch(() => {});
    throw new BodyTooLargeError();
  }
  if (message.body === null) return '';
  const reader = message.body.getReader();
  const decoder = new TextDecoder('utf-8', {fatal: true});
  let size = 0;
  let text = '';
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maximumBytes) throw new BodyTooLargeError();
      text += decoder.decode(value, {stream: true});
    }
    return text + decoder.decode();
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
}
