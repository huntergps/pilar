/** PILAR ERP — Shared Helper: Email API (Resend, ElasticMail, SendGrid) */

// ---------- Types ----------

export interface EmailAccount {
  provider: 'resend' | 'elasticmail' | 'sendgrid';
  api_key: string;
  from_name: string;
  from_email: string;
  domain?: string;
}

export interface SmtpAccount {
  host: string;
  port: number;
  use_tls: boolean;
  from_name: string;
  from_email: string;
  username: string;
  password: string;
}

export interface EmailPayload {
  to: string | string[];
  cc?: string | string[];
  bcc?: string | string[];
  subject: string;
  html?: string;
  text?: string;
  reply_to?: string;
  attachments?: Array<{
    filename: string;
    content: string; // base64
    content_type: string;
  }>;
}

export interface EmailResult {
  message_id: string;
  provider: string;
}

// ---------- Main Send Function ----------

/**
 * Sends an email via the configured provider.
 * Dispatches to the correct provider implementation based on `acct.provider`.
 */
export async function sendEmail(
  acct: EmailAccount,
  payload: EmailPayload,
): Promise<EmailResult> {
  switch (acct.provider) {
    case 'resend':
      return sendViaResend(acct, payload);
    case 'elasticmail':
      return sendViaElasticMail(acct, payload);
    case 'sendgrid':
      return sendViaSendGrid(acct, payload);
    default:
      throw new Error(`Unsupported email provider: ${acct.provider}`);
  }
}

// ---------- Resend ----------

async function sendViaResend(
  acct: EmailAccount,
  payload: EmailPayload,
): Promise<EmailResult> {
  const body: Record<string, unknown> = {
    from: `${acct.from_name} <${acct.from_email}>`,
    to: toArray(payload.to),
    subject: payload.subject,
  };

  if (payload.cc) body.cc = toArray(payload.cc);
  if (payload.bcc) body.bcc = toArray(payload.bcc);
  if (payload.html) body.html = payload.html;
  if (payload.text) body.text = payload.text;
  if (payload.reply_to) body.reply_to = payload.reply_to;

  if (payload.attachments?.length) {
    body.attachments = payload.attachments.map((a) => ({
      filename: a.filename,
      content: a.content,
      content_type: a.content_type,
    }));
  }

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${acct.api_key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Resend send failed (${res.status}): ${errText}`);
  }

  const result: { id: string } = await res.json();
  return { message_id: result.id, provider: 'resend' };
}

// ---------- ElasticMail ----------

async function sendViaElasticMail(
  acct: EmailAccount,
  payload: EmailPayload,
): Promise<EmailResult> {
  const recipients = toArray(payload.to).map((email) => ({ Email: email }));

  const bodyParts: Array<{ ContentType: string; Content: string }> = [];
  if (payload.html) bodyParts.push({ ContentType: 'HTML', Content: payload.html });
  if (payload.text) bodyParts.push({ ContentType: 'PlainText', Content: payload.text });

  const body: Record<string, unknown> = {
    Recipients: {
      To: recipients,
    },
    Content: {
      From: `${acct.from_name} <${acct.from_email}>`,
      Subject: payload.subject,
      Body: bodyParts,
    },
  };

  if (payload.reply_to) {
    (body.Content as Record<string, unknown>).ReplyTo = payload.reply_to;
  }

  if (payload.cc) {
    (body.Recipients as Record<string, unknown>).CC = toArray(payload.cc).map((email) => ({
      Email: email,
    }));
  }

  if (payload.bcc) {
    (body.Recipients as Record<string, unknown>).BCC = toArray(payload.bcc).map((email) => ({
      Email: email,
    }));
  }

  if (payload.attachments?.length) {
    (body.Content as Record<string, unknown>).Attachments = payload.attachments.map((a) => ({
      Name: a.filename,
      ContentType: a.content_type,
      Content: a.content,
    }));
  }

  const res = await fetch('https://api.elasticemail.com/v4/emails/transactional', {
    method: 'POST',
    headers: {
      'X-ElasticEmail-ApiKey': acct.api_key,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`ElasticMail send failed (${res.status}): ${errText}`);
  }

  const result: { TransactionID: string } = await res.json();
  return { message_id: result.TransactionID, provider: 'elasticmail' };
}

// ---------- SendGrid ----------

async function sendViaSendGrid(
  acct: EmailAccount,
  payload: EmailPayload,
): Promise<EmailResult> {
  const toAddresses = toArray(payload.to).map((email) => ({ email }));

  const personalization: Record<string, unknown> = {
    to: toAddresses,
  };

  if (payload.cc) {
    personalization.cc = toArray(payload.cc).map((email) => ({ email }));
  }

  if (payload.bcc) {
    personalization.bcc = toArray(payload.bcc).map((email) => ({ email }));
  }

  const content: Array<{ type: string; value: string }> = [];
  if (payload.text) content.push({ type: 'text/plain', value: payload.text });
  if (payload.html) content.push({ type: 'text/html', value: payload.html });
  // SendGrid requires at least one content entry
  if (content.length === 0) content.push({ type: 'text/plain', value: '' });

  const body: Record<string, unknown> = {
    personalizations: [personalization],
    from: { email: acct.from_email, name: acct.from_name },
    subject: payload.subject,
    content,
  };

  if (payload.reply_to) {
    body.reply_to = { email: payload.reply_to };
  }

  if (payload.attachments?.length) {
    body.attachments = payload.attachments.map((a) => ({
      content: a.content,
      filename: a.filename,
      type: a.content_type,
      disposition: 'attachment',
    }));
  }

  const res = await fetch('https://api.sendgrid.com/v3/mail/send', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${acct.api_key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`SendGrid send failed (${res.status}): ${errText}`);
  }

  // SendGrid returns 202 with message-id in header
  const messageId = res.headers.get('x-message-id') ?? 'sent';
  return { message_id: messageId, provider: 'sendgrid' };
}

// ---------- Helpers ----------

function toArray(value: string | string[]): string[] {
  return Array.isArray(value) ? value : [value];
}
