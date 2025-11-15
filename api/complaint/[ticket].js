// api/complaint/[ticket].js
export const config = { runtime: "nodejs" };

import {
  setCors,
  ok,
  bad,
  noContent,
  methodNotAllowed,
  readJson,
} from "../_lib/http.js";
import { getAuthUser } from "../_lib/auth.js";
import { complaintGet, complaintUpdate, Status } from "../_lib/store.js";
import { sendMail } from "../_lib/mailer.js";

const ADMIN_SECRET = process.env.ADMIN_SECRET || "";

function adminAuthorized(req) {
  const hdr = req.headers?.["x-admin-secret"];
  return !!(hdr && ADMIN_SECRET && hdr === ADMIN_SECRET);
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === "OPTIONS") return noContent(res);

  const { ticket } = req.query || {};
  if (!ticket) return bad(res, "missing ticket", 400);

  // GET: Authentifizierter Kunde darf sein Ticket sehen
  if (req.method === "GET") {
    const user = getAuthUser(req);
    if (!user) return bad(res, "unauthorized", 401);
    const comp = await complaintGet(ticket);
    if (!comp) return bad(res, "not found", 404);
    if (comp.email !== user.email) return bad(res, "forbidden", 403);
    return ok(res, comp);
  }

  // POST: Kunde reicht zusätzliche Anhänge nach
  if (req.method === "POST") {
    const user = getAuthUser(req);
    if (!user?.email) return bad(res, "unauthorized", 401);

    const comp = await complaintGet(ticket);
    if (!comp) return bad(res, "not found", 404);

    const userMail = (user.email || "").toString().trim().toLowerCase();
    const compMail = (comp.email || "").toString().trim().toLowerCase();
    if (!userMail || userMail !== compMail) return bad(res, "forbidden", 403);

    const body = readJson(req);
    const files = Array.isArray(body?.files) ? body.files : [];
    if (!files.length) return bad(res, "files required", 400);

    const MAX_BYTES = 8 * 1024 * 1024; // 8 MB gesamt
    let totalBytes = 0;
    const meta = [];
    const mailAttachments = [];

    for (let i = 0; i < files.length; i += 1) {
      const raw = files[i] || {};
      const name = (raw.name || `attachment_${i + 1}`).toString();
      const mime = (raw.mime || "application/octet-stream").toString();
      const base64 = ((raw.bytes || raw.data || "") + "").trim();
      if (!base64) continue;

      let buffer;
      try {
        buffer = Buffer.from(base64, "base64");
      } catch (err) {
        console.warn(
          "[complaint][attachments] invalid base64",
          err?.message || err,
        );
        return bad(res, "invalid file encoding", 400);
      }

      if (!buffer.length) continue;
      totalBytes += buffer.length;
      if (totalBytes > MAX_BYTES) return bad(res, "files too large", 400);

      meta.push({ name, mime, size: buffer.length });
      mailAttachments.push({
        filename: name || `attachment_${i + 1}.bin`,
        content: buffer,
        contentType: mime || "application/octet-stream",
      });
    }

    if (!meta.length) return bad(res, "files required", 400);

    const existing = Array.isArray(comp.uploads) ? comp.uploads : [];
    const updated = await complaintUpdate(ticket, {
      uploads: [...existing, ...meta],
    });

    try {
      const { send } = await import("../_lib/mail.js");
      const summary = `Neue Anhänge für Ticket ${ticket}\nKunde: ${comp.email || user.email}\nAnzahl: ${meta.length}\nGesamtgröße: ${Math.round(totalBytes / 1024)} KB`;
      await send(
        "complaint@dfs-diamon.de",
        {
          subject: `[DFS Complaint] Neue Anhänge ${ticket}`,
          text: summary,
          lang: "de",
        },
        mailAttachments,
      );

      await send(user.email, {
        subject: `[DFS Complaint] Anhänge erhalten (${ticket})`,
        text: `Vielen Dank. Wir haben Ihre Anhänge zu Ticket ${ticket} erhalten und an das DFS Team weitergeleitet.`,
        lang: "de",
      });
    } catch (mailErr) {
      console.error(
        "[complaint][attachments] mail failed",
        mailErr?.message || mailErr,
      );
    }

    return ok(res, {
      ok: true,
      uploaded: meta.length,
      totalBytes,
      uploads: updated?.uploads || meta,
    });
  }

  // PATCH: Admin ändert Status/decision/reportLink
  if (req.method === "PATCH") {
    if (!adminAuthorized(req)) return bad(res, "admin unauthorized", 401);
    const body =
      typeof req.body === "object" ? req.body : JSON.parse(req.body ?? "{}");

    const patch = {};
    if (body.status != null) {
      const s = Number(body.status);
      if (![1, 2, 3, 4, 5, 6].includes(s))
        return bad(res, "invalid status", 400);
      patch.status = s;
    }
    if (body.decision != null) {
      if (!["accepted", "rejected", null].includes(body.decision))
        return bad(res, "invalid decision", 400);
      patch.decision = body.decision;
    }
    if (body.reportLink != null) {
      patch.reportLink = body.reportLink || null;
    }

    let updated = await complaintUpdate(ticket, patch);
    if (!updated) return bad(res, "not found", 404);

    // Wenn abgelehnt -> automatisch abgeschlossen (rot), wie gewünscht
    if (updated.decision === "rejected" && updated.status !== Status.CLOSED) {
      updated = await complaintUpdate(ticket, { status: Status.CLOSED });
    }

    // Mail an Kunden bei Statusänderung/Entscheidung
    await sendMail({
      to: updated.email,
      subject: `[DFS Complaint] Update zu ${ticket} (Status ${updated.status}${updated.decision ? ` / ${updated.decision}` : ""})`,
      html: `
        <p>Ihr Reklamationsstatus wurde aktualisiert.</p>
        <p><strong>Ticket:</strong> ${ticket}<br/>
           <strong>Status:</strong> ${updated.status}${updated.decision ? ` (${updated.decision})` : ""}</p>
        ${updated.reportLink ? `<p><a href="${updated.reportLink}">Reklamationsbericht</a></p>` : ""}
      `,
    });

    return ok(res, updated);
  }

  return methodNotAllowed(res);
}
