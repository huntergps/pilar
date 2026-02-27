/**
 * Tests unitarios para email-api.ts
 *
 * Ejecutar: deno test foundation/supabase/functions/_shared/email-api.test.ts
 *
 * Cubre:
 *   · sendEmail → Resend: URL, headers, body, message_id
 *   · sendEmail → ElasticMail: URL, headers, body, TransactionID
 *   · sendEmail → SendGrid: URL, headers, body, message-id desde header
 *   · sendEmail → proveedor desconocido lanza Error
 *   · soporte multi-destinatario (to como array)
 *   · adjuntos incluidos en payload
 *   · cc/bcc forwarding por proveedor
 */

import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';

import { sendEmail, type EmailAccount, type EmailPayload } from './email-api.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface CapturedRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: unknown;
}

/** Instala un fetch mock que captura la petición y responde con `responseBody`. */
function mockFetch(
  responseBody: string,
  status = 200,
  extraHeaders: Record<string, string> = {},
): { captured: CapturedRequest[]; restore: () => void } {
  const captured: CapturedRequest[] = [];
  const originalFetch = globalThis.fetch;

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
    const initHeaders = (init?.headers ?? {}) as Record<string, string>;
    captured.push({
      url,
      method: (init?.method ?? 'GET') as string,
      headers: initHeaders,
      body: JSON.parse((init?.body as string) ?? '{}'),
    });
    return new Response(responseBody, {
      status,
      headers: { 'Content-Type': 'application/json', ...extraHeaders },
    });
  };

  return { captured, restore: () => { globalThis.fetch = originalFetch; } };
}

// Base accounts
const resendAccount: EmailAccount = {
  provider: 'resend',
  api_key: 're_test_key',
  from_name: 'PILAR ERP',
  from_email: 'noreply@pilar.ec',
};

const elasticAccount: EmailAccount = {
  provider: 'elasticmail',
  api_key: 'em_test_key',
  from_name: 'PILAR ERP',
  from_email: 'noreply@pilar.ec',
};

const sendgridAccount: EmailAccount = {
  provider: 'sendgrid',
  api_key: 'sg_test_key',
  from_name: 'PILAR ERP',
  from_email: 'noreply@pilar.ec',
};

const basePayload: EmailPayload = {
  to: 'cliente@empresa.ec',
  subject: 'Factura Autorizada FAC-001',
  html: '<p>Su factura fue autorizada.</p>',
  text: 'Su factura fue autorizada.',
};

// ---------------------------------------------------------------------------
// Resend
// ---------------------------------------------------------------------------

Deno.test('sendEmail Resend — POST a api.resend.com con Bearer token', async () => {
  const { captured, restore } = mockFetch(JSON.stringify({ id: 're_msg_001' }));
  try {
    const result = await sendEmail(resendAccount, basePayload);

    assertEquals(result.message_id, 're_msg_001');
    assertEquals(result.provider, 'resend');
    assertEquals(captured[0].url, 'https://api.resend.com/emails');
    assertEquals(captured[0].method, 'POST');
    assertEquals(
      (captured[0].headers as Record<string, string>)['Authorization'],
      'Bearer re_test_key',
    );
  } finally {
    restore();
  }
});

Deno.test('sendEmail Resend — body incluye from, to, subject, html, text', async () => {
  const { captured, restore } = mockFetch(JSON.stringify({ id: 're_001' }));
  try {
    await sendEmail(resendAccount, basePayload);
    const body = captured[0].body as Record<string, unknown>;

    assertEquals(body.from, 'PILAR ERP <noreply@pilar.ec>');
    assertEquals(body.to, ['cliente@empresa.ec']);
    assertEquals(body.subject, 'Factura Autorizada FAC-001');
    assertEquals(body.html, '<p>Su factura fue autorizada.</p>');
    assertEquals(body.text, 'Su factura fue autorizada.');
  } finally {
    restore();
  }
});

Deno.test('sendEmail Resend — array de destinatarios se mantiene como array', async () => {
  const { captured, restore } = mockFetch(JSON.stringify({ id: 're_002' }));
  try {
    await sendEmail(resendAccount, {
      ...basePayload,
      to: ['a@test.com', 'b@test.com'],
    });
    const body = captured[0].body as Record<string, unknown>;
    assertEquals(body.to, ['a@test.com', 'b@test.com']);
  } finally {
    restore();
  }
});

Deno.test('sendEmail Resend — adjuntos incluidos en body', async () => {
  const { captured, restore } = mockFetch(JSON.stringify({ id: 're_003' }));
  try {
    await sendEmail(resendAccount, {
      ...basePayload,
      attachments: [
        { filename: 'factura.pdf', content: 'base64data==', content_type: 'application/pdf' },
      ],
    });
    const body = captured[0].body as Record<string, unknown>;
    const attachments = body.attachments as unknown[];
    assertEquals(attachments.length, 1);
    assertEquals((attachments[0] as Record<string, string>).filename, 'factura.pdf');
  } finally {
    restore();
  }
});

Deno.test('sendEmail Resend — error HTTP lanza Error con status', async () => {
  const { restore } = mockFetch('{"statusCode":422,"name":"missing_required_field"}', 422);
  try {
    await assertRejects(
      () => sendEmail(resendAccount, { ...basePayload, subject: '' }),
      Error,
      'Resend send failed (422)',
    );
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// ElasticMail
// ---------------------------------------------------------------------------

Deno.test('sendEmail ElasticMail — POST a api.elasticemail.com con API key header', async () => {
  const { captured, restore } = mockFetch(
    JSON.stringify({ TransactionID: 'em_tx_001' }),
  );
  try {
    const result = await sendEmail(elasticAccount, basePayload);

    assertEquals(result.message_id, 'em_tx_001');
    assertEquals(result.provider, 'elasticmail');
    assertStringIncludes(captured[0].url, 'elasticemail.com');
    assertEquals(
      (captured[0].headers as Record<string, string>)['X-ElasticEmail-ApiKey'],
      'em_test_key',
    );
  } finally {
    restore();
  }
});

Deno.test('sendEmail ElasticMail — estructura Recipients.To correcta', async () => {
  const { captured, restore } = mockFetch(
    JSON.stringify({ TransactionID: 'em_tx_002' }),
  );
  try {
    await sendEmail(elasticAccount, basePayload);
    const body = captured[0].body as Record<string, unknown>;
    const recipients = (body.Recipients as Record<string, unknown>).To as Array<{ Email: string }>;
    assertEquals(recipients[0].Email, 'cliente@empresa.ec');
  } finally {
    restore();
  }
});

Deno.test('sendEmail ElasticMail — cc forwarded a Recipients.CC', async () => {
  const { captured, restore } = mockFetch(
    JSON.stringify({ TransactionID: 'em_003' }),
  );
  try {
    await sendEmail(elasticAccount, { ...basePayload, cc: 'cc@test.com' });
    const body = captured[0].body as Record<string, unknown>;
    const cc = (body.Recipients as Record<string, unknown>).CC as Array<{ Email: string }>;
    assertEquals(cc[0].Email, 'cc@test.com');
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// SendGrid
// ---------------------------------------------------------------------------

Deno.test('sendEmail SendGrid — POST a api.sendgrid.com con Bearer token', async () => {
  const { captured, restore } = mockFetch('', 202, {
    'x-message-id': 'sg_msg_001',
  });
  try {
    const result = await sendEmail(sendgridAccount, basePayload);

    assertEquals(result.message_id, 'sg_msg_001');
    assertEquals(result.provider, 'sendgrid');
    assertStringIncludes(captured[0].url, 'sendgrid.com');
    assertEquals(
      (captured[0].headers as Record<string, string>)['Authorization'],
      'Bearer sg_test_key',
    );
  } finally {
    restore();
  }
});

Deno.test('sendEmail SendGrid — personalizations con to array', async () => {
  const { captured, restore } = mockFetch('', 202, { 'x-message-id': 'sg_002' });
  try {
    await sendEmail(sendgridAccount, {
      ...basePayload,
      to: ['x@test.com', 'y@test.com'],
    });
    const body = captured[0].body as Record<string, unknown>;
    const personalization = (body.personalizations as Record<string, unknown>[])[0];
    const toEmails = (personalization.to as Array<{ email: string }>).map((t) => t.email);
    assertEquals(toEmails, ['x@test.com', 'y@test.com']);
  } finally {
    restore();
  }
});

Deno.test('sendEmail SendGrid — cuando x-message-id ausente retorna "sent"', async () => {
  const { restore } = mockFetch('', 202); // sin header x-message-id
  try {
    const result = await sendEmail(sendgridAccount, basePayload);
    assertEquals(result.message_id, 'sent');
  } finally {
    restore();
  }
});

Deno.test('sendEmail SendGrid — content mínimo cuando no hay html ni text', async () => {
  const { captured, restore } = mockFetch('', 202, { 'x-message-id': 'sg_003' });
  try {
    await sendEmail(sendgridAccount, {
      to: 'a@b.com',
      subject: 'Empty',
      // sin html ni text
    });
    const body = captured[0].body as Record<string, unknown>;
    const content = body.content as Array<{ type: string; value: string }>;
    assertEquals(content.length, 1);
    assertEquals(content[0].type, 'text/plain');
    assertEquals(content[0].value, '');
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// Proveedor desconocido
// ---------------------------------------------------------------------------

Deno.test('sendEmail — proveedor desconocido lanza Error', async () => {
  await assertRejects(
    () =>
      sendEmail(
        { ...(resendAccount as unknown as EmailAccount), provider: 'unknown' as 'resend' },
        basePayload,
      ),
    Error,
    'Unsupported email provider',
  );
});
