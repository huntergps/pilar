/** PILAR ERP — Shared Helper: Telegram Bot API */

const TG_API_BASE = 'https://api.telegram.org';

// ---------- Types ----------

export interface TgAccount {
  bot_token: string;
  bot_username: string;
  webhook_secret: string;
}

export type TgSendType = 'message' | 'photo' | 'document' | 'audio' | 'video' | 'animation' | 'voice';

export interface TgMessagePayload {
  text?: string;
  parse_mode?: 'HTML' | 'MarkdownV2' | 'Markdown';
  photo?: string; // file_id or URL
  document?: string;
  audio?: string;
  video?: string;
  animation?: string;
  voice?: string;
  caption?: string;
  reply_markup?: object; // InlineKeyboardMarkup etc
  reply_to_message_id?: number;
}

export interface TgSendResult {
  message_id: number;
  chat: { id: number; type: string };
  date: number;
}

// ---------- Signature Verification ----------

/**
 * Verifies the X-Telegram-Bot-Api-Secret-Token header.
 * Telegram sends this header on webhook requests when a secret is configured.
 */
export function verifyTelegramSecret(
  headerValue: string | null,
  secret: string,
): boolean {
  if (headerValue === null) return false;
  return headerValue === secret;
}

// ---------- Send ----------

/** Maps TgSendType to the Telegram Bot API method name. */
const METHOD_MAP: Record<TgSendType, string> = {
  message: 'sendMessage',
  photo: 'sendPhoto',
  document: 'sendDocument',
  audio: 'sendAudio',
  video: 'sendVideo',
  animation: 'sendAnimation',
  voice: 'sendVoice',
};

/**
 * Sends a message (text, media, etc.) to a Telegram chat.
 * Returns the Telegram message ID as a string.
 */
export async function tgSend(
  token: string,
  chatId: string | number,
  type: TgSendType,
  payload: TgMessagePayload,
): Promise<string> {
  const method = METHOD_MAP[type];
  if (!method) {
    throw new Error(`Unsupported Telegram send type: ${type}`);
  }

  const body: Record<string, unknown> = { chat_id: chatId };

  switch (type) {
    case 'message':
      body.text = payload.text;
      if (payload.parse_mode) body.parse_mode = payload.parse_mode;
      if (payload.reply_markup) body.reply_markup = payload.reply_markup;
      if (payload.reply_to_message_id) body.reply_to_message_id = payload.reply_to_message_id;
      break;
    case 'photo':
      body.photo = payload.photo;
      if (payload.caption) body.caption = payload.caption;
      if (payload.parse_mode) body.parse_mode = payload.parse_mode;
      if (payload.reply_markup) body.reply_markup = payload.reply_markup;
      break;
    case 'document':
      body.document = payload.document;
      if (payload.caption) body.caption = payload.caption;
      break;
    case 'audio':
      body.audio = payload.audio;
      if (payload.caption) body.caption = payload.caption;
      break;
    case 'video':
      body.video = payload.video;
      if (payload.caption) body.caption = payload.caption;
      break;
    case 'animation':
      body.animation = payload.animation;
      if (payload.caption) body.caption = payload.caption;
      break;
    case 'voice':
      body.voice = payload.voice;
      if (payload.caption) body.caption = payload.caption;
      break;
  }

  const res = await fetch(`${TG_API_BASE}/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Telegram ${method} failed (${res.status}): ${errText}`);
  }

  const result: { ok: boolean; result: TgSendResult } = await res.json();
  if (!result.ok) {
    throw new Error(`Telegram ${method} returned ok=false`);
  }

  return String(result.result.message_id);
}

// ---------- File Download ----------

/**
 * Downloads a file from Telegram servers.
 * First retrieves the file path via getFile, then downloads the binary content.
 */
export async function tgDownloadFile(
  token: string,
  fileId: string,
): Promise<Uint8Array> {
  // Step 1: Get file path
  const metaRes = await fetch(
    `${TG_API_BASE}/bot${token}/getFile?file_id=${encodeURIComponent(fileId)}`,
  );

  if (!metaRes.ok) {
    const errText = await metaRes.text();
    throw new Error(`Telegram getFile failed (${metaRes.status}): ${errText}`);
  }

  const meta: { ok: boolean; result: { file_path: string } } = await metaRes.json();
  if (!meta.ok) {
    throw new Error('Telegram getFile returned ok=false');
  }

  // Step 2: Download the file
  const fileRes = await fetch(
    `${TG_API_BASE}/file/bot${token}/${meta.result.file_path}`,
  );

  if (!fileRes.ok) {
    throw new Error(`Telegram file download failed (${fileRes.status})`);
  }

  return new Uint8Array(await fileRes.arrayBuffer());
}
