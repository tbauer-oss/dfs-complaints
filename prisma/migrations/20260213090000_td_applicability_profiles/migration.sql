-- Enums
CREATE TYPE "TdApplicabilityState" AS ENUM ('MANDATORY', 'OPTIONAL', 'CONDITIONAL', 'NOT_APPLICABLE');
CREATE TYPE "TdProductProfileType" AS ENUM ('ROTARY_REUSABLE_NONSTERILE', 'ROTARY_REUSABLE_SURGICAL', 'DENTAL_ALLOYS', 'SOFTWARE_DEVICE');
CREATE TYPE "TdPackagingType" AS ENUM ('BULK_NONSTERILE', 'UNIT_NONSTERILE', 'STERILE_BARRIER_SYSTEM', 'TRANSPORT_VALIDATED');

-- Tables
CREATE TABLE "TdApplicabilityProfile" (
  "id" TEXT NOT NULL,
  "tdId" TEXT NOT NULL,
  "profileType" "TdProductProfileType" NOT NULL,
  "isReusable" BOOLEAN NOT NULL,
  "isSterile" BOOLEAN NOT NULL,
  "packagingType" "TdPackagingType" NOT NULL,
  "classificationRule" TEXT,
  "hasSoftware" BOOLEAN NOT NULL,
  "notes" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TdApplicabilityProfile_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "TdApplicabilityOverride" (
  "id" TEXT NOT NULL,
  "tdId" TEXT NOT NULL,
  "sectionId" TEXT,
  "queryKey" TEXT,
  "state" "TdApplicabilityState" NOT NULL,
  "conditionKey" TEXT,
  "conditionExpr" TEXT,
  "rationale" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TdApplicabilityOverride_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "TdApplicabilityResult" (
  "id" TEXT NOT NULL,
  "tdId" TEXT NOT NULL,
  "sectionId" TEXT,
  "queryKey" TEXT,
  "state" "TdApplicabilityState" NOT NULL,
  "isConditionMet" BOOLEAN,
  "conditionSummary" TEXT,
  "generatedBy" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TdApplicabilityResult_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "TdApplicabilityProfile_tdId_key" ON "TdApplicabilityProfile"("tdId");
CREATE INDEX "TdApplicabilityOverride_tdId_idx" ON "TdApplicabilityOverride"("tdId");
CREATE INDEX "TdApplicabilityResult_tdId_idx" ON "TdApplicabilityResult"("tdId");
CREATE UNIQUE INDEX "TdApplicabilityResult_tdId_sectionId_queryKey_key" ON "TdApplicabilityResult"("tdId", "sectionId", "queryKey");

ALTER TABLE "TdApplicabilityProfile" ADD CONSTRAINT "TdApplicabilityProfile_tdId_fkey" FOREIGN KEY ("tdId") REFERENCES "TdFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "TdApplicabilityOverride" ADD CONSTRAINT "TdApplicabilityOverride_tdId_fkey" FOREIGN KEY ("tdId") REFERENCES "TdFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "TdApplicabilityResult" ADD CONSTRAINT "TdApplicabilityResult_tdId_fkey" FOREIGN KEY ("tdId") REFERENCES "TdFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill defaults for existing TDs
INSERT INTO "TdApplicabilityProfile" ("id", "tdId", "profileType", "isReusable", "isSterile", "packagingType", "classificationRule", "hasSoftware", "createdAt", "updatedAt")
SELECT
  concat('tdap_', substring(md5(t."id") from 1 for 16)),
  t."id",
  'ROTARY_REUSABLE_NONSTERILE'::"TdProductProfileType",
  TRUE,
  FALSE,
  'BULK_NONSTERILE'::"TdPackagingType",
  t."rule",
  FALSE,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "TdFile" t
LEFT JOIN "TdApplicabilityProfile" ap ON ap."tdId" = t."id"
WHERE ap."id" IS NULL;
