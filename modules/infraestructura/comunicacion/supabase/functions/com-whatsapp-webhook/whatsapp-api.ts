/** PILAR ERP — Shared Helper: WhatsApp Cloud API v23.0 */

const WA_API_BASE = 'https://graph.facebook.com/v23.0';

// ---------- Types ----------

export interface WaAccount {
  app_uid: string;
  account_uid: string;
  phone_uid: string;
  phone_number: string;
  token: string;
  app_secret: string;
  webhook_verify_token: string;
}

export interface WaTemplateComponent {
  type: 'header' | 'body' | 'button';
  parameters?: WaTemplateParameter[];
  sub_type?: 'url' | 'quick_reply';
  index?: number;
}

export interface WaTemplateParameter {
  type: 'text' | 'currency' | 'date_time' | 'image' | 'document' | 'video';
  text?: string;
  currency?: { fallback_value: string; code: string; amount_1000: number };
  image?: { id?: string; link?: string };
  document?: { id?: string; link?: string; filename?: string };
  video?: { id?: string; link?: string };
}

export interface WaMessagePayload {
  type: 'text' | 'template' | 'image' | 'document' | 'audio' | 'video' | 'interactive' | 'reaction';
  text?: { body: string; preview_url?: boolean };
  template?: {
    name: string;
    language: { code: string };
    components?: WaTemplateComponent[];
  };
  image?: { id?: string; link?: string; caption?: string };
  document?: { id?: string; link?: string; filename?: string; caption?: string };
  audio?: { id?: string; link?: string };
  video?: { id?: string; link?: string; caption?: string };
  interactive?: object;
  reaction?: { message_id: string; emoji: string };
}

export interface WaSendResult {
  messages: Array<{ id: string }>;
  contacts: Array<{ input: string; wa_id: string }>;
}

// ---------- Signature Verification ----------

/**
 * Verifies the HMAC-SHA256 signature from Meta webhook payloads.
 * The `signature` header arrives as "sha256=XXXX".
 */
export async function verifyWaSignature(
  body: string,
  signature: string,
  secret: string,
): Promise<boolean> {
  if (!signature.startsWith('sha256=')) return false;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signed = await crypto.subtle.sign('HMAC', key, encoder.encode(body));
  const hex = Array.from(new Uint8Array(signed))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  const expected = signature.slice('sha256='.length);

  // Constant-time comparison
  if (hex.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < hex.length; i++) {
    diff |= hex.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

// ---------- Send Message ----------

/**
 * Sends a WhatsApp message via Cloud API.
 * Returns the `wamid` (WhatsApp message ID).
 */
export async function waSend(
  acct: WaAccount,
  to: string,
  payload: WaMessagePayload,
  parentMsgId?: string,
): Promise<string> {
  const body: Record<string, unknown> = {
    messaging_product: 'whatsapp',
    recipient_type: 'individual',
    to,
    ...payload,
  };

  if (parentMsgId) {
    body.context = { message_id: parentMsgId };
  }

  const res = await fetch(`${WA_API_BASE}/${acct.phone_uid}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${acct.token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`WhatsApp send failed (${res.status}): ${errText}`);
  }

  const result: WaSendResult = await res.json();
  return result.messages[0].id;
}

// ---------- Media Upload ----------

/**
 * Uploads media to WhatsApp Cloud API.
 * Returns the media ID.
 */
export async function waUploadMedia(
  acct: WaAccount,
  bytes: Uint8Array,
  mime: string,
  name: string,
): Promise<string> {
  const form = new FormData();
  form.append('file', new Blob([bytes], { type: mime }), name);
  form.append('type', mime);
  form.append('messaging_product', 'whatsapp');

  const res = await fetch(`${WA_API_BASE}/${acct.phone_uid}/media`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${acct.token}` },
    body: form,
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`WhatsApp media upload failed (${res.status}): ${errText}`);
  }

  const result: { id: string } = await res.json();
  return result.id;
}

// ---------- Media Download ----------

/**
 * Downloads media from WhatsApp Cloud API.
 * First retrieves the URL, then downloads the actual bytes.
 */
export async function waDownloadMedia(
  acct: WaAccount,
  mediaId: string,
): Promise<Uint8Array> {
  // Step 1: Get media URL
  const metaRes = await fetch(`${WA_API_BASE}/${mediaId}`, {
    headers: { Authorization: `Bearer ${acct.token}` },
  });

  if (!metaRes.ok) {
    const errText = await metaRes.text();
    throw new Error(`WhatsApp media metadata failed (${metaRes.status}): ${errText}`);
  }

  const meta: { url: string } = await metaRes.json();

  // Step 2: Download the file
  const fileRes = await fetch(meta.url, {
    headers: { Authorization: `Bearer ${acct.token}` },
  });

  if (!fileRes.ok) {
    throw new Error(`WhatsApp media download failed (${fileRes.status})`);
  }

  return new Uint8Array(await fileRes.arrayBuffer());
}

// ---------- Templates ----------

/**
 * Fetches message templates from Meta Business account.
 * If `fetchAll` is true, paginates through all results.
 */
export async function waGetTemplates(
  acct: WaAccount,
  fetchAll?: boolean,
): Promise<object[]> {
  const templates: object[] = [];
  let url = `${WA_API_BASE}/${acct.account_uid}/message_templates?limit=200&fields=id,name,status,quality_score,category,language,components`;

  do {
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${acct.token}` },
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`WhatsApp get templates failed (${res.status}): ${errText}`);
    }

    const result: { data: object[]; paging?: { cursors?: { after?: string }; next?: string } } =
      await res.json();
    templates.push(...result.data);

    if (fetchAll && result.paging?.next) {
      url = result.paging.next;
    } else {
      break;
    }
  } while (true);

  return templates;
}

/**
 * Submits a new message template to the Meta Business account.
 * Returns the template ID.
 */
export async function waSubmitTemplate(
  acct: WaAccount,
  payload: object,
): Promise<string> {
  const res = await fetch(`${WA_API_BASE}/${acct.account_uid}/message_templates`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${acct.token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`WhatsApp submit template failed (${res.status}): ${errText}`);
  }

  const result: { id: string } = await res.json();
  return result.id;
}

/**
 * Updates an existing message template.
 */
export async function waUpdateTemplate(
  acct: WaAccount,
  templateUid: string,
  payload: object,
): Promise<void> {
  const res = await fetch(`${WA_API_BASE}/${templateUid}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${acct.token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`WhatsApp update template failed (${res.status}): ${errText}`);
  }
}

// ---------- Helpers ----------

/**
 * Builds a template message payload ready for `waSend`.
 */
export function buildTemplatePayload(
  name: string,
  lang: string,
  components: WaTemplateComponent[],
): WaMessagePayload {
  return {
    type: 'template',
    template: {
      name,
      language: { code: lang },
      components,
    },
  };
}

/**
 * Formats a phone number to E.164 format (digits only, no '+' prefix).
 */
export function formatWaNumber(phone: string): string {
  return phone.replace(/[^\d]/g, '');
}
