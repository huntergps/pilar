/**
 * PILAR ERP — Edge Function: com-telegram-webhook
 *
 * Recibe webhooks de Telegram Bot API.
 * URL esperada: POST /com-telegram-webhook?account_id=UUID
 *
 * Auth: verify_jwt: false (Telegram no envia JWT)
 * Verificacion: X-Telegram-Bot-Api-Secret-Token debe coincidir con
 *               cuenta.config_json.webhook_secret
 *
 * Procesa:
 *   - update.message        → texto + media (foto/video/audio/doc/sticker/voz)
 *   - update.callback_query → callback de botones inline
 *
 * Media: descarga via getFile, sube a Storage bucket 'com-media',
 *        almacena URL pública en adjuntos_json del mensaje.
 *
 * Responde 200 siempre (Telegram reinicia webhook si no recibe ACK <1s)
 */

import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from '@supabase/supabase-js';

// ---------------------------------------------------------------------------
// Supabase admin client
// ---------------------------------------------------------------------------

function getAdminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
}

// ---------------------------------------------------------------------------
// Tipos de media Telegram
// ---------------------------------------------------------------------------

type TipoMedia = 'imagen' | 'video' | 'audio' | 'voz' | 'documento' | 'sticker' | 'video_nota';

interface MediaInfo {
  file_id: string;
  file_unique_id: string;
  mime_type?: string;
  file_size?: number;
  file_name?: string;
  tipo: TipoMedia;
}

interface Adjunto {
  tipo: TipoMedia;
  url: string;
  nombre: string;
  mime_type: string;
  tamano: number;
}

// ---------------------------------------------------------------------------
// Extraer media del mensaje Telegram
// ---------------------------------------------------------------------------

function extraerMedia(msg: any): MediaInfo | null {
  if (msg.photo) {
    // photo es array de PhotoSize — usar el más grande
    const largest = msg.photo.reduce((a: any, b: any) =>
      (a.file_size ?? 0) > (b.file_size ?? 0) ? a : b,
    );
    return {
      file_id: largest.file_id,
      file_unique_id: largest.file_unique_id,
      mime_type: 'image/jpeg',
      file_size: largest.file_size,
      file_name: `photo_${largest.file_unique_id}.jpg`,
      tipo: 'imagen',
    };
  }
  if (msg.video) {
    return {
      file_id: msg.video.file_id,
      file_unique_id: msg.video.file_unique_id,
      mime_type: msg.video.mime_type ?? 'video/mp4',
      file_size: msg.video.file_size,
      file_name: msg.video.file_name ?? `video_${msg.video.file_unique_id}.mp4`,
      tipo: 'video',
    };
  }
  if (msg.audio) {
    return {
      file_id: msg.audio.file_id,
      file_unique_id: msg.audio.file_unique_id,
      mime_type: msg.audio.mime_type ?? 'audio/mpeg',
      file_size: msg.audio.file_size,
      file_name: msg.audio.file_name ?? `audio_${msg.audio.file_unique_id}.mp3`,
      tipo: 'audio',
    };
  }
  if (msg.voice) {
    return {
      file_id: msg.voice.file_id,
      file_unique_id: msg.voice.file_unique_id,
      mime_type: msg.voice.mime_type ?? 'audio/ogg',
      file_size: msg.voice.file_size,
      file_name: `voice_${msg.voice.file_unique_id}.ogg`,
      tipo: 'voz',
    };
  }
  if (msg.document) {
    return {
      file_id: msg.document.file_id,
      file_unique_id: msg.document.file_unique_id,
      mime_type: msg.document.mime_type ?? 'application/octet-stream',
      file_size: msg.document.file_size,
      file_name: msg.document.file_name ?? `doc_${msg.document.file_unique_id}`,
      tipo: 'documento',
    };
  }
  if (msg.sticker) {
    return {
      file_id: msg.sticker.file_id,
      file_unique_id: msg.sticker.file_unique_id,
      mime_type: msg.sticker.is_animated ? 'application/x-tgsticker' : 'image/webp',
      file_size: msg.sticker.file_size,
      file_name: `sticker_${msg.sticker.file_unique_id}.webp`,
      tipo: 'sticker',
    };
  }
  if (msg.video_note) {
    return {
      file_id: msg.video_note.file_id,
      file_unique_id: msg.video_note.file_unique_id,
      mime_type: 'video/mp4',
      file_size: msg.video_note.file_size,
      file_name: `video_note_${msg.video_note.file_unique_id}.mp4`,
      tipo: 'video_nota',
    };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Descargar de Telegram y subir a Supabase Storage
// ---------------------------------------------------------------------------

async function subirMedia(
  botToken: string,
  mediaInfo: MediaInfo,
  empresaId: string,
  convId: string,
  supabase: ReturnType<typeof getAdminClient>,
): Promise<Adjunto | null> {
  try {
    // 1. Obtener ruta del archivo en Telegram
    const getFileRes = await fetch(
      `https://api.telegram.org/bot${botToken}/getFile?file_id=${mediaInfo.file_id}`,
    );
    const getFileData = await getFileRes.json();
    if (!getFileData.ok || !getFileData.result?.file_path) {
      console.warn('[com-telegram-webhook] getFile failed:', getFileData.description);
      return null;
    }
    const filePath = getFileData.result.file_path;

    // 2. Descargar archivo desde Telegram CDN
    const fileRes = await fetch(
      `https://api.telegram.org/file/bot${botToken}/${filePath}`,
    );
    if (!fileRes.ok) {
      console.warn('[com-telegram-webhook] File download failed:', fileRes.status);
      return null;
    }
    const fileBuffer = await fileRes.arrayBuffer();

    // 3. Subir a Supabase Storage: com-media/{empresaId}/{convId}/{nombre}
    const storagePath = `${empresaId}/${convId}/${mediaInfo.file_name}`;
    const { error: uploadError } = await supabase.storage
      .from('com-media')
      .upload(storagePath, fileBuffer, {
        contentType: mediaInfo.mime_type ?? 'application/octet-stream',
        upsert: true,
      });

    if (uploadError) {
      console.error('[com-telegram-webhook] Storage upload error:', uploadError.message);
      return null;
    }

    // 4. Obtener URL pública
    const { data: urlData } = supabase.storage
      .from('com-media')
      .getPublicUrl(storagePath);

    return {
      tipo: mediaInfo.tipo,
      url: urlData.publicUrl,
      nombre: mediaInfo.file_name ?? 'archivo',
      mime_type: mediaInfo.mime_type ?? 'application/octet-stream',
      tamano: mediaInfo.file_size ?? 0,
    };
  } catch (err) {
    console.error('[com-telegram-webhook] subirMedia error:', err instanceof Error ? err.message : err);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const url = new URL(req.url);
  const accountId = url.searchParams.get('account_id');

  if (!accountId) {
    console.warn('[com-telegram-webhook] Missing account_id query param');
    return new Response('OK', { status: 200 });
  }

  // 1. Look up the account
  const supabase = getAdminClient();
  const { data: cuenta, error: cuentaError } = await supabase
    .from('com_cuentas')
    .select('*')
    .eq('id', accountId)
    .eq('tipo', 'telegram')
    .eq('activo', true)
    .single();

  if (cuentaError || !cuenta) {
    console.error(
      `[com-telegram-webhook] Cannot load account ${accountId}:`,
      cuentaError?.message ?? 'not found',
      cuentaError?.details ?? '',
    );
    return new Response('OK', { status: 200 });
  }

  // 2. Verify secret token header
  const secretHeader = req.headers.get('x-telegram-bot-api-secret-token');
  const expectedSecret: string = cuenta.config_json?.webhook_secret ?? '';

  if (!expectedSecret || secretHeader !== expectedSecret) {
    console.warn('[com-telegram-webhook] Invalid or missing secret token');
    return new Response('Unauthorized', { status: 401 });
  }

  // 3. Parse body
  let update: any;
  try {
    update = await req.json();
  } catch {
    console.error('[com-telegram-webhook] Invalid JSON body');
    return new Response('OK', { status: 200 });
  }

  const botToken: string = cuenta.config_json?.bot_token ?? '';

  // 4. Process message
  if (update.message) {
    const msg = update.message;
    const firstName = msg.from?.first_name ?? '';
    const lastName = msg.from?.last_name ?? '';
    const nombre = `${firstName} ${lastName}`.trim();

    // Texto: usar caption de media si no hay texto directo
    const cuerpo = msg.text ?? msg.caption ?? null;

    // Determinar texto de display para mensajes solo-media sin caption
    const cuerpoDisplay = cuerpo ?? (() => {
      if (msg.photo)      return '📷 Foto';
      if (msg.video)      return '🎥 Video';
      if (msg.audio)      return '🎵 Audio';
      if (msg.voice)      return '🎤 Nota de voz';
      if (msg.document)   return `📎 ${msg.document.file_name ?? 'Archivo'}`;
      if (msg.sticker)    return `${msg.sticker.emoji ?? '🎭'} Sticker`;
      if (msg.video_note) return '⭕ Video nota';
      return '[media]';
    })();

    // Registrar mensaje base
    const { data: rpcData, error: rpcError } = await supabase.rpc(
      'com_registrar_mensaje_inbound',
      {
        p_cuenta_id:         cuenta.id,
        p_canal:             'telegram',
        p_destinatario_ref:  String(msg.chat.id),
        p_destinatario_nombre: nombre || null,
        p_cuerpo:            cuerpoDisplay,
        p_mensaje_uid:       String(msg.message_id),
        p_padre_uid:         msg.reply_to_message
          ? String(msg.reply_to_message.message_id)
          : null,
        p_meta_json: { chat_type: msg.chat.type, from_id: msg.from?.id },
      },
    );

    if (rpcError) {
      console.error(
        '[com-telegram-webhook] RPC error (message):',
        rpcError.message, rpcError.details ?? '', rpcError.hint ?? '',
      );
    } else {
      console.info('[com-telegram-webhook] Message registered:', JSON.stringify(rpcData));

      // Si hay media, descargar y subir a Storage en background
      const mediaInfo = extraerMedia(msg);
      if (mediaInfo && rpcData?.msg_id && rpcData?.conv_id && botToken) {
        const adjunto = await subirMedia(
          botToken, mediaInfo,
          cuenta.empresa_id, rpcData.conv_id,
          supabase,
        );
        if (adjunto) {
          await supabase
            .from('com_mensajes')
            .update({ adjuntos_json: [adjunto] })
            .eq('id', rpcData.msg_id);
          console.info('[com-telegram-webhook] Media subida:', adjunto.url);
        }
      }
    }
  }

  // 5. Process callback query
  if (update.callback_query) {
    const cq = update.callback_query;
    const chatId = cq.message?.chat?.id ?? cq.from.id;

    const { data: rpcData, error: rpcError } = await supabase.rpc(
      'com_registrar_mensaje_inbound',
      {
        p_cuenta_id:          cuenta.id,
        p_canal:              'telegram',
        p_destinatario_ref:   String(chatId),
        p_destinatario_nombre: cq.from.first_name || null,
        p_cuerpo:             `[callback] ${cq.data}`,
        p_mensaje_uid:        cq.id,
        p_padre_uid:          cq.message ? String(cq.message.message_id) : null,
        p_meta_json:          { callback_data: cq.data, from_id: cq.from.id },
      },
    );

    if (rpcError) {
      console.error(
        '[com-telegram-webhook] RPC error (callback_query):',
        rpcError.message, rpcError.details ?? '', rpcError.hint ?? '',
      );
    } else {
      console.info('[com-telegram-webhook] Callback registered:', JSON.stringify(rpcData));
    }
  }

  return new Response('OK', { status: 200 });
});
