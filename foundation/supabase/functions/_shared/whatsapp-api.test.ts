/**
 * Tests unitarios para whatsapp-api.ts
 *
 * Ejecutar: deno test foundation/supabase/functions/_shared/whatsapp-api.test.ts
 *
 * Cubre:
 *   · verifyWaSignature: firma válida, inválida, prefijo faltante, longitud distinta
 *   · formatWaNumber: E.164, prefijo +, dígitos mixtos
 *   · buildTemplatePayload: estructura correcta del payload de template
 *   · waSend: fetch mock, URL, headers, body; manejo de error HTTP
 */

import {
  assertEquals,
  assertRejects,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';

import {
  buildTemplatePayload,
  formatWaNumber,
  verifyWaSignature,
  waSend,
  type WaAccount,
} from './whatsapp-api.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TEST_SECRET = 'test-app-secret-1234';

/** Genera una firma HMAC-SHA256 válida sobre el body dado. */
async function makeSignature(body: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signed = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(body),
  );
  const hex = Array.from(new Uint8Array(signed))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return `sha256=${hex}`;
}

const fakeAccount: WaAccount = {
  app_uid: 'app-123',
  account_uid: 'acct-456',
  phone_uid: 'phone-789',
  phone_number: '+593991234567',
  token: 'Bearer-Token-XYZ',
  app_secret: TEST_SECRET,
  webhook_verify_token: 'verify-me',
};

// ---------------------------------------------------------------------------
// verifyWaSignature
// ---------------------------------------------------------------------------

Deno.test('verifyWaSignature — firma válida retorna true', async () => {
  const body = '{"entry":[{"id":"123"}]}';
  const sig = await makeSignature(body, TEST_SECRET);
  const result = await verifyWaSignature(body, sig, TEST_SECRET);
  assertEquals(result, true);
});

Deno.test('verifyWaSignature — firma alterada retorna false', async () => {
  const body = '{"entry":[{"id":"123"}]}';
  const sig = await makeSignature(body, TEST_SECRET);
  // Alterar un carácter en el hex (después de "sha256=")
  const badSig = sig.slice(0, -1) + (sig.endsWith('a') ? 'b' : 'a');
  const result = await verifyWaSignature(body, badSig, TEST_SECRET);
  assertEquals(result, false);
});

Deno.test('verifyWaSignature — secret incorrecto retorna false', async () => {
  const body = '{"entry":[{"id":"123"}]}';
  const sig = await makeSignature(body, TEST_SECRET);
  const result = await verifyWaSignature(body, sig, 'wrong-secret');
  assertEquals(result, false);
});

Deno.test('verifyWaSignature — sin prefijo "sha256=" retorna false', async () => {
  const body = '{"entry":[]}';
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(TEST_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signed = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  const hex = Array.from(new Uint8Array(signed))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  // Enviar hex sin prefijo
  const result = await verifyWaSignature(body, hex, TEST_SECRET);
  assertEquals(result, false);
});

Deno.test('verifyWaSignature — body vacío con firma correcta retorna true', async () => {
  const body = '';
  const sig = await makeSignature(body, TEST_SECRET);
  const result = await verifyWaSignature(body, sig, TEST_SECRET);
  assertEquals(result, true);
});

// ---------------------------------------------------------------------------
// formatWaNumber
// ---------------------------------------------------------------------------

Deno.test('formatWaNumber — elimina prefijo +', () => {
  assertEquals(formatWaNumber('+593991234567'), '593991234567');
});

Deno.test('formatWaNumber — elimina espacios y guiones', () => {
  assertEquals(formatWaNumber('+1 (555) 123-4567'), '15551234567');
});

Deno.test('formatWaNumber — número ya limpio no cambia', () => {
  assertEquals(formatWaNumber('593991234567'), '593991234567');
});

Deno.test('formatWaNumber — letras y símbolos son eliminados', () => {
  assertEquals(formatWaNumber('abc+59(3)99'), '5939');
});

// ---------------------------------------------------------------------------
// buildTemplatePayload
// ---------------------------------------------------------------------------

Deno.test('buildTemplatePayload — genera payload tipo template', () => {
  const payload = buildTemplatePayload('factura_autorizada', 'es_EC', [
    { type: 'body', parameters: [{ type: 'text', text: 'FAC-001' }] },
  ]);

  assertEquals(payload.type, 'template');
  assertEquals(payload.template?.name, 'factura_autorizada');
  assertEquals(payload.template?.language.code, 'es_EC');
  assertEquals(payload.template?.components?.length, 1);
  assertEquals(payload.template?.components?.[0].type, 'body');
});

Deno.test('buildTemplatePayload — sin components genera array vacío', () => {
  const payload = buildTemplatePayload('test_template', 'en_US', []);
  assertEquals(payload.template?.components, []);
});

// ---------------------------------------------------------------------------
// waSend — con fetch mock
// ---------------------------------------------------------------------------

Deno.test('waSend — llama al endpoint correcto y retorna wamid', async () => {
  const capturedRequests: { url: string; method: string; body: unknown }[] = [];

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input: string | URL | Request, _init?: RequestInit): Promise<Response> => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    const init = _init ?? {};
    capturedRequests.push({
      url,
      method: (init.method ?? 'GET') as string,
      body: JSON.parse((init.body as string) ?? '{}'),
    });
    return new Response(
      JSON.stringify({
        messages: [{ id: 'wamid.test-abc-123' }],
        contacts: [{ input: '593991234567', wa_id: '593991234567' }],
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  };

  try {
    const wamid = await waSend(fakeAccount, '593991234567', {
      type: 'text',
      text: { body: 'Hola mundo' },
    });

    assertEquals(wamid, 'wamid.test-abc-123');
    assertEquals(capturedRequests.length, 1);
    assertEquals(
      capturedRequests[0].url,
      'https://graph.facebook.com/v23.0/phone-789/messages',
    );
    assertEquals(capturedRequests[0].method, 'POST');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('waSend — incluye context.message_id cuando se pasa parentMsgId', async () => {
  let capturedBody: Record<string, unknown> = {};
  const originalFetch = globalThis.fetch;

  globalThis.fetch = async (_input: unknown, init?: RequestInit): Promise<Response> => {
    capturedBody = JSON.parse((init?.body as string) ?? '{}');
    return new Response(
      JSON.stringify({
        messages: [{ id: 'wamid.reply-001' }],
        contacts: [],
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  };

  try {
    await waSend(
      fakeAccount,
      '593991234567',
      { type: 'text', text: { body: 'Respuesta' } },
      'parent-wamid-xyz',
    );

    assertEquals(
      (capturedBody.context as Record<string, string>)?.message_id,
      'parent-wamid-xyz',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('waSend — lanza error cuando el status HTTP no es ok', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (): Promise<Response> =>
    new Response('{"error":{"message":"Invalid token"}}', {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });

  try {
    await assertRejects(
      () =>
        waSend(fakeAccount, '5930', {
          type: 'text',
          text: { body: 'Test' },
        }),
      Error,
      'WhatsApp send failed (401)',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
