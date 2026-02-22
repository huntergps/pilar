/**
 * PILAR ERP — Shared: notification-templates
 *
 * Motor de sustitución de variables para plantillas de notificación multi-canal.
 * Soporta sintaxis {{nombre_variable}} compatible con los templates almacenados
 * en la tabla `plantillas_notificacion`.
 *
 * Uso:
 *   import { renderTemplate, htmlToPlainText, getUnresolvedVars }
 *     from '../_shared/notification-templates.ts'
 */

// ---------------------------------------------------------------------------
// renderTemplate
// ---------------------------------------------------------------------------

/**
 * Reemplaza todas las ocurrencias de `{{clave}}` con el valor correspondiente
 * del mapa `vars`.
 *
 * - Si la clave no existe en `vars`, la variable se deja tal cual (sin lanzar
 *   error), ya que algunas variables son opcionales (ej. `{{url_ride}}`).
 * - Reemplaza TODAS las ocurrencias (flag `g`).
 * - Las claves de las variables solo pueden contener letras, dígitos y `_`
 *   (patrón `\w+`).
 *
 * @param template  Cadena con variables `{{clave}}` a sustituir.
 * @param vars      Mapa clave → valor. Los valores deben ser strings.
 * @returns         Cadena con las variables sustituidas.
 */
export function renderTemplate(
  template: string,
  vars: Record<string, string>,
): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_match, key: string) => {
    return Object.prototype.hasOwnProperty.call(vars, key) ? vars[key] : `{{${key}}}`;
  });
}

// ---------------------------------------------------------------------------
// htmlToPlainText
// ---------------------------------------------------------------------------

/**
 * Convierte HTML a texto plano realizando:
 *   1. Reemplaza etiquetas de bloque (`<br>`, `<p>`, `</p>`, `<li>`) por `\n`.
 *   2. Elimina todas las demás etiquetas HTML con `<[^>]+>`.
 *   3. Decodifica entidades HTML básicas: `&amp;`, `&lt;`, `&gt;`, `&nbsp;`,
 *      `&quot;`, `&#39;`.
 *   4. Colapsa secuencias de espacios/tabulaciones múltiples a un solo espacio.
 *   5. Colapsa más de dos saltos de línea consecutivos a exactamente dos.
 *   6. Recorta espacios al inicio y al final del resultado.
 *
 * Se usa principalmente para generar el campo `text` del email (fallback de
 * accesibilidad recomendado por Resend) y el cuerpo de mensajes WhatsApp/Telegram
 * cuando la plantilla solo tiene versión HTML.
 *
 * @param html  Cadena HTML de entrada.
 * @returns     Texto plano equivalente.
 */
export function htmlToPlainText(html: string): string {
  // Paso 1: etiquetas de bloque → salto de línea
  let text = html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<p(?:\s[^>]*)?>/gi, '\n')
    .replace(/<li(?:\s[^>]*)?>/gi, '\n');

  // Paso 2: eliminar todas las demás etiquetas
  text = text.replace(/<[^>]+>/g, '');

  // Paso 3: decodificar entidades HTML básicas
  text = text
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'");

  // Paso 4: colapsar espacios múltiples (sin afectar saltos de línea)
  text = text.replace(/[^\S\n]+/g, ' ');

  // Paso 5: colapsar más de dos saltos de línea consecutivos
  text = text.replace(/\n{3,}/g, '\n\n');

  // Paso 6: recortar
  return text.trim();
}

// ---------------------------------------------------------------------------
// getUnresolvedVars
// ---------------------------------------------------------------------------

/**
 * Retorna la lista de variables `{{clave}}` que quedaron sin sustituir en una
 * cadena ya renderizada con `renderTemplate`.
 *
 * Útil para depuración y para alertas de configuración (ej. detectar que una
 * plantilla referencia `{{url_ride}}` pero el dato no fue provisto).
 *
 * @param rendered  Cadena resultado de `renderTemplate`.
 * @returns         Array de nombres de variables no sustituidas (sin `{{}}`).
 *                  Array vacío si todas las variables fueron resueltas.
 */
export function getUnresolvedVars(rendered: string): string[] {
  const matches = rendered.matchAll(/\{\{(\w+)\}\}/g);
  const unresolved: string[] = [];
  for (const match of matches) {
    if (!unresolved.includes(match[1])) {
      unresolved.push(match[1]);
    }
  }
  return unresolved;
}
