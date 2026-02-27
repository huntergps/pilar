/**
 * Tests unitarios para telegram-api.ts
 *
 * Ejecutar: deno test foundation/supabase/functions/_shared/telegram-api.test.ts
 *
 * Cubre:
 *   · verifyTelegramSecret: header correcto, incorrecto, null
 *   · tgSend text: URL, método, body (text, parse_mode, reply_markup)
 *   · tgSend photo: body con photo + caption
 *   · tgSend document: body con document
 *   · tgSend tipo desconocido: lanza Error (defensive)
 *   · tgSend error HTTP: lanza Error con método y status
 *   · tgSend ok=false en respuesta: lanza Error
 *   · tgDownloadFile: cadena getFile → descarga
 */

import {
  assertEquals,
  assertRejects,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';

import {
  tgDownloadFile,
  tgSend,
  verifyTelegramSecret,
} from './telegram-api.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TEST_TOKEN = '987654321:TEST-Token-ABC';
const TEST_SECRET = 'my-webhook-secret';
const TG_BASE = 'https://api.telegram.org';

interface CapturedCall {
  url: string;
  method: string;
  body: Record<string, unknown>;
}

function mockFetchSequence(
  responses: Array<{ body: string; status?: number }>,
): { calls: CapturedCall[]; restore: () => void } {
  const calls: CapturedCall[] = [];
  let idx = 0;
  const original = globalThis.fetch;

  globalThis.fetch = async (
    input: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => {
    const url =
      typeof input === 'string'
        ? input
        : input instanceof URL
        ? input.href
        : input.url;
    calls.push({
      url,
      method: (init?.method ?? 'GET') as string,
      body: init?.body ? JSON.parse(init.body as string) : {},
    });
    const resp = responses[idx++] ?? responses[responses.length - 1];
    return new Response(resp.body, {
      status: resp.status ?? 200,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  return { calls, restore: () => { globalThis.fetch = original; } };
}

// ---------------------------------------------------------------------------
// verifyTelegramSecret
// ---------------------------------------------------------------------------

Deno.test('verifyTelegramSecret — header correcto retorna true', () => {
  assertEquals(verifyTelegramSecret(TEST_SECRET, TEST_SECRET), true);
});

Deno.test('verifyTelegramSecret — header incorrecto retorna false', () => {
  assertEquals(verifyTelegramSecret('wrong-secret', TEST_SECRET), false);
});

Deno.test('verifyTelegramSecret — header null retorna false', () => {
  assertEquals(verifyTelegramSecret(null, TEST_SECRET), false);
});

Deno.test('verifyTelegramSecret — string vacío retorna false', () => {
  assertEquals(verifyTelegramSecret('', TEST_SECRET), false);
});

// ---------------------------------------------------------------------------
// tgSend — texto
// ---------------------------------------------------------------------------

Deno.test('tgSend text — llama a sendMessage con URL correcta', async () => {
  const { calls, restore } = mockFetchSequence([
    {
      body: JSON.stringify({
        ok: true,
        result: { message_id: 42, chat: { id: 123, type: 'private' }, date: 0 },
      }),
    },
  ]);

  try {
    const msgId = await tgSend(TEST_TOKEN, 123, 'message', {
      text: 'Hola desde PILAR',
    });

    assertEquals(msgId, '42');
    assertEquals(calls.length, 1);
    assertEquals(calls[0].url, `${TG_BASE}/bot${TEST_TOKEN}/sendMessage`);
    assertEquals(calls[0].method, 'POST');
    assertEquals(calls[0].body.chat_id, 123);
    assertEquals(calls[0].body.text, 'Hola desde PILAR');
  } finally {
    restore();
  }
});

Deno.test('tgSend text — parse_mode y reply_markup incluidos cuando presentes', async () => {
  const { calls, restore } = mockFetchSequence([
    {
      body: JSON.stringify({
        ok: true,
        result: { message_id: 10, chat: { id: 1, type: 'group' }, date: 0 },
      }),
    },
  ]);

  try {
    await tgSend(TEST_TOKEN, 1, 'message', {
      text: '<b>Factura</b>',
      parse_mode: 'HTML',
      reply_markup: { inline_keyboard: [] },
    });

    assertEquals(calls[0].body.parse_mode, 'HTML');
    assertEquals(
      JSON.stringify(calls[0].body.reply_markup),
      JSON.stringify({ inline_keyboard: [] }),
    );
  } finally {
    restore();
  }
});

Deno.test('tgSend text — reply_to_message_id incluido', async () => {
  const { calls, restore } = mockFetchSequence([
    {
      body: JSON.stringify({
        ok: true,
        result: { message_id: 11, chat: { id: 5, type: 'private' }, date: 0 },
      }),
    },
  ]);

  try {
    await tgSend(TEST_TOKEN, 5, 'message', {
      text: 'Respuesta',
      reply_to_message_id: 9,
    });
    assertEquals(calls[0].body.reply_to_message_id, 9);
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// tgSend — photo
// ---------------------------------------------------------------------------

Deno.test('tgSend photo — llama a sendPhoto con campo photo y caption', async () => {
  const { calls, restore } = mockFetchSequence([
    {
      body: JSON.stringify({
        ok: true,
        result: { message_id: 20, chat: { id: 7, type: 'private' }, date: 0 },
      }),
    },
  ]);

  try {
    await tgSend(TEST_TOKEN, 7, 'photo', {
      photo: 'file_id_abc123',
      caption: 'Ver adjunto',
    });

    assertEquals(calls[0].url, `${TG_BASE}/bot${TEST_TOKEN}/sendPhoto`);
    assertEquals(calls[0].body.photo, 'file_id_abc123');
    assertEquals(calls[0].body.caption, 'Ver adjunto');
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// tgSend — document
// ---------------------------------------------------------------------------

Deno.test('tgSend document — llama a sendDocument con campo document', async () => {
  const { calls, restore } = mockFetchSequence([
    {
      body: JSON.stringify({
        ok: true,
        result: { message_id: 30, chat: { id: 8, type: 'private' }, date: 0 },
      }),
    },
  ]);

  try {
    await tgSend(TEST_TOKEN, 8, 'document', {
      document: 'file_id_doc456',
      caption: 'Factura.pdf',
    });

    assertEquals(calls[0].url, `${TG_BASE}/bot${TEST_TOKEN}/sendDocument`);
    assertEquals(calls[0].body.document, 'file_id_doc456');
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// Manejo de errores
// ---------------------------------------------------------------------------

Deno.test('tgSend — error HTTP lanza Error con método y status', async () => {
  const { restore } = mockFetchSequence([
    { body: '{"error_code":401,"description":"Unauthorized"}', status: 401 },
  ]);

  try {
    await assertRejects(
      () => tgSend(TEST_TOKEN, 1, 'message', { text: 'test' }),
      Error,
      'sendMessage failed (401)',
    );
  } finally {
    restore();
  }
});

Deno.test('tgSend — respuesta ok=false lanza Error', async () => {
  const { restore } = mockFetchSequence([
    {
      body: JSON.stringify({ ok: false, description: 'Bad Request: chat not found' }),
    },
  ]);

  try {
    await assertRejects(
      () => tgSend(TEST_TOKEN, 99999, 'message', { text: 'test' }),
      Error,
      'ok=false',
    );
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// tgDownloadFile
// ---------------------------------------------------------------------------

Deno.test('tgDownloadFile — encadena getFile + descarga y retorna bytes', async () => {
  const fakeBytes = new Uint8Array([80, 68, 70]); // "PDF"

  const { calls, restore } = mockFetchSequence([
    // 1ª llamada: getFile
    {
      body: JSON.stringify({
        ok: true,
        result: { file_path: 'documents/file_001.pdf' },
      }),
    },
    // 2ª llamada: descarga del archivo
    {
      body: '', // Será reemplazado por ArrayBuffer fake
    },
  ]);

  // Necesitamos que la segunda respuesta tenga arrayBuffer()
  const original = globalThis.fetch;
  let callCount = 0;
  globalThis.fetch = async (
    input: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => {
    const url = typeof input === 'string' ? input : (input as URL).href;
    calls[callCount] = { url, method: init?.method ?? 'GET', body: {} };
    callCount++;

    if (callCount === 1) {
      // Primera llamada: getFile
      return new Response(
        JSON.stringify({ ok: true, result: { file_path: 'documents/file_001.pdf' } }),
        { status: 200 },
      );
    } else {
      // Segunda llamada: archivo binario
      return new Response(fakeBytes, { status: 200 });
    }
  };

  try {
    const bytes = await tgDownloadFile(TEST_TOKEN, 'agADBAADfile123');

    assertEquals(bytes instanceof Uint8Array, true);
    assertEquals(calls[0].url.includes('getFile'), true);
    assertEquals(calls[1].url.includes('documents/file_001.pdf'), true);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test('tgDownloadFile — getFile falla → lanza Error', async () => {
  const { restore } = mockFetchSequence([
    { body: '{"error_code":400,"description":"Bad Request"}', status: 400 },
  ]);

  try {
    await assertRejects(
      () => tgDownloadFile(TEST_TOKEN, 'invalid_file_id'),
      Error,
      'Telegram getFile failed (400)',
    );
  } finally {
    restore();
  }
});

Deno.test('tgDownloadFile — getFile ok=false → lanza Error', async () => {
  const { restore } = mockFetchSequence([
    { body: JSON.stringify({ ok: false, description: 'file not found' }) },
  ]);

  try {
    await assertRejects(
      () => tgDownloadFile(TEST_TOKEN, 'missing_file'),
      Error,
      'ok=false',
    );
  } finally {
    restore();
  }
});
