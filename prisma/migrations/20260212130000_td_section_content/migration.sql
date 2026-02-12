-- Add TD section content storage
CREATE TABLE IF NOT EXISTS "TdSectionContent" (
  "id" TEXT PRIMARY KEY,
  "sectionId" TEXT NOT NULL UNIQUE,
  "summaryMarkdown" TEXT NOT NULL DEFAULT '',
  "contentJson" JSONB,
  "updatedByUserId" TEXT,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TdSectionContent_sectionId_fkey" FOREIGN KEY ("sectionId") REFERENCES "TdSection"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "TdSectionContent_updatedAt_idx" ON "TdSectionContent"("updatedAt");

-- Backfill one content row per existing section
INSERT INTO "TdSectionContent" ("id", "sectionId", "summaryMarkdown", "contentJson", "updatedByUserId", "updatedAt", "createdAt")
SELECT
  CONCAT('tdsc_', SUBSTRING(md5(random()::text || clock_timestamp()::text) FROM 1 FOR 16)),
  s."id",
  '',
  NULL,
  NULL,
  NOW(),
  NOW()
FROM "TdSection" s
LEFT JOIN "TdSectionContent" c ON c."sectionId" = s."id"
WHERE c."id" IS NULL;
