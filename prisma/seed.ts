import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const templates = [
  ['ANNEX_II_A', 'A. Device description and specification', 'Including variants and accessories.', 10, 'ANNEX_II'],
  ['ANNEX_II_B', 'B. Information supplied by manufacturer', 'Labeling / IFU and claims.', 20, 'ANNEX_II'],
  ['ANNEX_II_C', 'C. Design and manufacturing information', 'Critical processes and manufacturing controls.', 30, 'ANNEX_II'],
  ['ANNEX_II_D', 'D. General Safety & Performance Requirements (GSPR)', 'Linked to GSPR assessments.', 40, 'ANNEX_II'],
  ['ANNEX_II_E', 'E. Benefit-risk and risk management', 'Linked to FMEA and risk files.', 50, 'ANNEX_II'],
  ['ANNEX_II_F', 'F. Product verification and validation', 'V&V, biocompatibility, sterilization, software as applicable.', 60, 'ANNEX_II'],
  ['ANNEX_III_G', 'G. PMS plan', 'Post-market surveillance planning.', 70, 'ANNEX_III'],
  ['ANNEX_III_H', 'H. PMS report / PSUR / PMCF', 'PMS outcomes and PMCF evidence as applicable.', 80, 'ANNEX_III'],
] as const;

async function main() {
  for (const [key, name, description, order, annex] of templates) {
    await prisma.tdSectionTemplate.upsert({
      where: { key },
      update: { name, description, order, annex },
      create: { key, name, description, order, annex },
    });
  }
}

main().finally(async () => {
  await prisma.$disconnect();
});
