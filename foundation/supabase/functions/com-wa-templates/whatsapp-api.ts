/** PILAR ERP — Shared Helper: WhatsApp Cloud API v23.0 + BSP adapters (360dialog, Twilio) */

// ---------- BSP Types ----------

/** Business Solution Provider for WhatsApp API access. */
export type WaBspType = 'meta' | '360dialog' | 'twilio';

const WA_META_BASE = 'https://graph.facebook.com/v23.0';
const WA_360DIALOG_BASE = 'https://waba.360dialog.io/v1';

// ---------- Types ----------

/**
 * WhatsApp account credentials stored in `com_cuentas.config_json`.
 * Uses a flat interface; only relevant fields per BSP are populated.
 */
export interface WaAccount {
  bsp?: WaBspType;          // default: 'meta'
  webhook_verify_token: string;

  // Meta & 360dialog shared
  phone_uid?: string;       // Meta: Phone Number ID; 360dialog: channel_id
  phone_number?: string;    // E.164 format (with or without +)

  // Meta-specific
  app_uid?: string;
  account_uid?: string;
  token?: string;           // Permanent access token
  app_secret?: string;      // For HMAC-SHA256 webhook verification

  // 360dialog-specific
  api_key?: string;         // D360-API-KEY
  waba_id?: string;         // 360dialog WABA ID (equiv. to account_uid)

  // Twilio-specific
  account_sid?: string;     // AC...
  auth_token?: string;      // For Basic Auth + webhook HMAC-SHA1
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
 * Verifies the HMAC-SHA256 signature from Meta or 360dialog webhook payloads.
 * - Meta: header `x-hub-signature-256`, secret = app_secret
 * - 360dialog: header `x-360dialog-signature`, secret = api_key
 * The signature header arrives as "sha256=XXXX".
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

/**
 * Verifies the HMAC-SHA1 signature from Twilio webhook requests.
 * Twilio signs: full URL + sorted POST params (key+value concatenated), signed with auth_token.
 * The header `X-Twilio-Signature` contains base64(HMAC-SHA1).
 */
export async function verifyTwilioSignature(
  authToken: string,
  signature: string,
  url: string,
  params: Record<string, string>,
): Promise<boolean> {
  if (!signature) return false;

  const sortedKeys = Object.keys(params).sort();
  let toSign = url;
  for (const key of sortedKeys) {
    toSign += key + (params[key] ?? '');
  }

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(authToken),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign'],
  );

  const signed = await crypto.subtle.sign('HMAC', key, encoder.encode(toSign));
  const computed = btoa(String.fromCharCode(...new Uint8Array(signed)));

  return computed === signature;
}

// ---------- Send Message ----------

/**
 * Sends a WhatsApp message via the BSP configured in the account.
 * Routes to Meta Cloud API, 360dialog, or Twilio based on `acct.bsp`.
 * Returns the provider message ID (wamid for Meta/360dialog, sid for Twilio).
 */
export async function waSend(
  acct: WaAccount,
  to: string,
  payload: WaMessagePayload,
  parentMsgId?: string,
): Promise<string> {
  const bsp = acct.bsp ?? 'meta';
  switch (bsp) {
    case '360dialog':
      return _waSend360dialog(acct, to, payload, parentMsgId);
    case 'twilio':
      return _waSendTwilio(acct, to, payload);
    default:
      return _waSendMeta(acct, to, payload, parentMsgId);
  }
}

/** Meta Cloud API send */
async function _waSendMeta(
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

  const res = await fetch(`${WA_META_BASE}/${acct.phone_uid}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${acct.token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`WhatsApp (Meta) send failed (${res.status}): ${errText}`);
  }

  const result: WaSendResult = await res.json();
  return result.messages[0].id;
}

/** 360dialog send — identical payload to Meta, different endpoint and auth header */
async function _waSend360dialog(
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

  const res = await fetch(`${WA_360DIALOG_BASE}/messages`, {
    method: 'POST',
    headers: {
      'D360-API-KEY': acct.api_key!,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`WhatsApp (360dialog) send failed (${res.status}): ${errText}`);
  }

  const result: WaSendResult = await res.json();
  return result.messages[0].id;
}

/**
 * Twilio WhatsApp send — uses form-encoded REST API.
 * Only supports text messages; template messages require ContentSid (not yet implemented).
 */
async function _waSendTwilio(
  acct: WaAccount,
  to: string,
  payload: WaMessagePayload,
): Promise<string> {
  if (payload.type !== 'text' || !payload.text) {
    throw new Error(`Twilio WhatsApp only supports 'text' messages; got: ${payload.type}`);
  }

  const fromNumber = formatWaNumber(acct.phone_number ?? '');
  const toNumber = formatWaNumber(to);

  const params = new URLSearchParams();
  params.set('From', `whatsapp:+${fromNumber}`);
  params.set('To', `whatsapp:+${toNumber}`);
  params.set('Body', payload.text.body);

  const credentials = btoa(`${acct.account_sid}:${acct.auth_token}`);

  const res = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${acct.account_sid}/Messages.json`,
    {
      method: 'POST',
      headers: {
        Authorization: `Basic ${credentials}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params.toString(),
    },
  );

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`WhatsApp (Twilio) send failed (${res.status}): ${errText}`);
  }

  const result: { sid: string } = await res.json();
  return result.sid;
}

// ---------- Media Upload ----------

/**
 * Uploads media to WhatsApp Cloud API (Meta or 360dialog).
 * Returns the media ID. Not supported for Twilio.
 */
export async function waUploadMedia(
  acct: WaAccount,
  bytes: Uint8Array,
  mime: string,
  name: string,
): Promise<string> {
  const bsp = acct.bsp ?? 'meta';
  const baseUrl = bsp === '360dialog' ? WA_360DIALOG_BASE : WA_META_BASE;
  const authHeader = bsp === '360dialog'
    ? { 'D360-API-KEY': acct.api_key! }
    : { Authorization: `Bearer ${acct.token}` };

  const form = new FormData();
  form.append('file', new Blob([bytes], { type: mime }), name);
  form.append('type', mime);
  form.append('messaging_product', 'whatsapp');

  const endpoint = bsp === '360dialog'
    ? `${baseUrl}/media`
    : `${baseUrl}/${acct.phone_uid}/media`;

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: authHeader,
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
 * Downloads media from WhatsApp Cloud API (Meta or 360dialog).
 * First retrieves the URL, then downloads the actual bytes.
 */
export async function waDownloadMedia(
  acct: WaAccount,
  mediaId: string,
): Promise<Uint8Array> {
  const bsp = acct.bsp ?? 'meta';
  const baseUrl = bsp === '360dialog' ? WA_360DIALOG_BASE : WA_META_BASE;
  const authHeader = bsp === '360dialog'
    ? { 'D360-API-KEY': acct.api_key! }
    : { Authorization: `Bearer ${acct.token}` };

  // Step 1: Get media URL
  const metaRes = await fetch(`${baseUrl}/${mediaId}`, { headers: authHeader });

  if (!metaRes.ok) {
    const errText = await metaRes.text();
    throw new Error(`WhatsApp media metadata failed (${metaRes.status}): ${errText}`);
  }

  const meta: { url: string } = await metaRes.json();

  // Step 2: Download the file
  const fileRes = await fetch(meta.url, { headers: authHeader });

  if (!fileRes.ok) {
    throw new Error(`WhatsApp media download failed (${fileRes.status})`);
  }

  return new Uint8Array(await fileRes.arrayBuffer());
}

// ---------- Templates (Meta & 360dialog) ----------

/**
 * Fetches message templates.
 * Meta: graph.facebook.com/{account_uid}/message_templates
 * 360dialog: waba.360dialog.io/v1/configs/templates
 * If `fetchAll` is true, paginates through all results.
 */
export async function waGetTemplates(
  acct: WaAccount,
  fetchAll?: boolean,
): Promise<object[]> {
  const bsp = acct.bsp ?? 'meta';

  if (bsp === 'twilio') {
    throw new Error('Twilio template management not supported via this API');
  }

  const templates: object[] = [];

  let url = bsp === '360dialog'
    ? `${WA_360DIALOG_BASE}/configs/templates`
    : `${WA_META_BASE}/${acct.account_uid}/message_templates?limit=200&fields=id,name,status,quality_score,category,language,components`;

  const authHeader = bsp === '360dialog'
    ? { 'D360-API-KEY': acct.api_key! }
    : { Authorization: `Bearer ${acct.token}` };

  do {
    const res = await fetch(url, { headers: authHeader });

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
 * Submits a new message template (Meta or 360dialog).
 * Returns the template ID.
 */
export async function waSubmitTemplate(
  acct: WaAccount,
  payload: object,
): Promise<string> {
  const bsp = acct.bsp ?? 'meta';

  if (bsp === 'twilio') {
    throw new Error('Twilio template management not supported via this API');
  }

  const url = bsp === '360dialog'
    ? `${WA_360DIALOG_BASE}/configs/templates`
    : `${WA_META_BASE}/${acct.account_uid}/message_templates`;

  const authHeader = bsp === '360dialog'
    ? { 'D360-API-KEY': acct.api_key!, 'Content-Type': 'application/json' }
    : { Authorization: `Bearer ${acct.token}`, 'Content-Type': 'application/json' };

  const res = await fetch(url, {
    method: 'POST',
    headers: authHeader,
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
 * Updates an existing message template (Meta only; 360dialog: submit new version).
 */
export async function waUpdateTemplate(
  acct: WaAccount,
  templateUid: string,
  payload: object,
): Promise<void> {
  const bsp = acct.bsp ?? 'meta';

  if (bsp === 'twilio') {
    throw new Error('Twilio template management not supported via this API');
  }

  const url = bsp === '360dialog'
    ? `${WA_360DIALOG_BASE}/configs/templates/${templateUid}`
    : `${WA_META_BASE}/${templateUid}`;

  const authHeader = bsp === '360dialog'
    ? { 'D360-API-KEY': acct.api_key!, 'Content-Type': 'application/json' }
    : { Authorization: `Bearer ${acct.token}`, 'Content-Type': 'application/json' };

  const res = await fetch(url, {
    method: 'POST',
    headers: authHeader,
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
