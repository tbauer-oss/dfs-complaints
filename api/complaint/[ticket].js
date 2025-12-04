// api/complaint/[ticket].js
export const config = {
  runtime: 'nodejs',
  api: {
    bodyParser: false,
  },
};

const BODY_LIMIT_BYTES = Number(process.env.API_BODY_LIMIT_BYTES || 64 * 1024 * 1024);

import {
  setCors,
  ok,
  bad,
  noContent,
  methodNotAllowed,
  readJsonBody,
} from '../_lib/http.js';
import { getAuthUser } from "../_lib/auth.js";
import {
  complaintGet,
  complaintUpdate,
  Status,
  userByEmail,
} from "../_lib/store.js";
import { sendMail } from "../_lib/mailer.js";
import { blobUploadsEnabled, processIncomingFiles } from "../_lib/uploads.js";
import { sendComplaintStatusPush } from '../_lib/push.js';
import { generateDualReportsForComplaint } from '../_lib/reporting.js';
import { normalizeReportLinksMap } from '../_lib/departments.js';

const ADMIN_SECRET = process.env.ADMIN_SECRET || "";

function adminAuthorized(req) {
  const hdr = req.headers?.["x-admin-secret"];
  return !!(hdr && ADMIN_SECRET && hdr === ADMIN_SECRET);
}

function firstNonEmpty(...values) {
  for (const value of values) {
    const str = (value ?? "").toString().trim();
    if (str) return str;
  }
  return "";
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

    let body;
    try {
      body = await readJsonBody(req, { limitBytes: BODY_LIMIT_BYTES });
    } catch (bodyErr) {
      const code = bodyErr?.statusCode || (bodyErr?.message === 'body too large' ? 413 : 400);
      const msg = bodyErr?.message || 'invalid body';
      return bad(res, msg, code);
    }
    const files = Array.isArray(body?.files) ? body.files : [];
    let processed;
    try {
      processed = await processIncomingFiles(files, {
        ticket,
        includeMailAttachments: true,
        allowPreviewFallback: !blobUploadsEnabled,
      });
    } catch (err) {
      const msg = err?.message === "files too large"
        ? "files too large"
        : err?.message === "invalid file encoding"
          ? "invalid file encoding"
          : "file upload failed";
      return bad(res, msg, 400);
    }

    if (!processed.uploads.length) return bad(res, "files required", 400);

    const existing = Array.isArray(comp.uploads) ? comp.uploads : [];
    const updated = await complaintUpdate(ticket, {
      uploads: [...existing, ...processed.uploads],
    });

    try {
      const { send } = await import("../_lib/mail.js");
      let account = null;
      try {
        account = comp?.email ? await userByEmail(comp.email) : null;
      } catch (err) {
        console.warn(
          "[complaint][attachments] userByEmail failed",
          err?.message || err,
        );
      }

      const payload = (comp?.payload && typeof comp.payload === "object")
        ? comp.payload
        : {};
      const company = firstNonEmpty(
        comp?.company,
        comp?.customer?.company,
        comp?.account?.company,
        payload?.customerName,
        payload?.company,
        payload?.companyName,
        payload?.firma,
        account?.company,
      );
      const customerEmail = firstNonEmpty(comp?.email, user.email);
      const summary = `Neue Anhänge für Ticket ${ticket}\nKunde: ${company || "(unbekannt)"}\nE-Mail: ${customerEmail}\nAnzahl: ${processed.uploads.length}\nGesamtgröße: ${Math.round((processed.totalBytes || 0) / 1024)} KB`;
      await send(
        "complaint@dfs-diamon.de",
        {
          subject: `[DFS Complaint] Neue Anhänge ${ticket}`,
          text: summary,
          lang: "de",
        },
        processed.attachments,
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
      uploaded: processed.uploads.length,
      totalBytes: processed.totalBytes || 0,
      uploads: updated?.uploads || processed.uploads,
    });
  }

  // PATCH: Admin ändert Status/decision/reportLink
  if (req.method === "PATCH") {
    if (!adminAuthorized(req)) return bad(res, "admin unauthorized", 401);

    let body;
    try {
      body = await readJsonBody(req, { limitBytes: BODY_LIMIT_BYTES });
    } catch (bodyErr) {
      const code =
        bodyErr?.statusCode ||
        (bodyErr?.message === "body too large" ? 413 : 400);
      const msg = bodyErr?.message || "invalid body";
      return bad(res, msg, code);
    }

    // NEU: Flag, ob eine Push-Benachrichtigung gewünscht ist
    const sendPushFlag =
      body?.sendPush === true ||
      body?.sendPush === 'true' ||
      body?.sendPush === 1 ||
      body?.sendPush === '1';

    const patch = {};
    if (body.status != null) {
      const s = Number(body.status);
      if (![1, 2, 3, 4, 5].includes(s))
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

    // Reklamation vorher laden, um alten Status zu kennen
    const before = await complaintGet(ticket);
    if (!before) return bad(res, "not found", 404);
    const oldStatus = before.status;

    let updated = await complaintUpdate(ticket, patch);
    if (!updated) return bad(res, "not found", 404);

    // Wenn abgelehnt -> automatisch abgeschlossen (rot), wie gewünscht
    if (updated.decision === "rejected" && updated.status !== Status.CLOSED) {
      updated = await complaintUpdate(ticket, { status: Status.CLOSED });
    }

    const newStatus = updated.status;
    const statusChanged =
      newStatus !== undefined &&
      oldStatus !== undefined &&
      newStatus !== oldStatus;

    const preferredLang = body?.reportLang || body?.reportLanguage;

    if (newStatus === Status.CLOSED) {
      try {
        const generated = await generateDualReportsForComplaint(updated, { preferredLang });
        if (generated) {
          const mergedExternal = normalizeReportLinksMap({
            ...(updated.externalReportLinks || {}),
            ...(generated.externalLinks || {}),
          });
          const mergedInternal = normalizeReportLinksMap({
            ...(updated.internalReportLinks || {}),
            ...(generated.internalLinks || {}),
          });
          const mergedReportLinks = normalizeReportLinksMap({
            ...(updated.reportLinks || {}),
            ...(generated.externalLinks || {}),
          });
          const defaultLink = mergedExternal[generated.lang]
            || mergedExternal.de
            || mergedExternal.en
            || Object.values(mergedExternal)[0];

          updated = await complaintUpdate(ticket, {
            externalReportLinks: mergedExternal,
            internalReportLinks: mergedInternal,
            reportLinks: mergedReportLinks,
            reportLink: defaultLink || updated.reportLink || null,
          });
        }
      } catch (err) {
        console.error('[complaint][ticket] report generation failed', err?.message || err);
      }
    }

    // NEU: nur wenn Status geändert UND sendPushFlag gesetzt → Push
    if (statusChanged && sendPushFlag) {
      try {
        await sendComplaintStatusPush(updated);
      } catch (err) {
        console.error(
          "[complaint] status push failed",
          err?.message || err
        );
      }
    }

    // Mail an Kunden bei Statusänderung/Entscheidung (wie bisher)
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
