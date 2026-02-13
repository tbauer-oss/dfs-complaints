# TD Template Engine (MDR-konform)

## 1) Unterpunkte unter „Struktur“ und Template-Zuordnung

| Unterpunkt | Query-Key | Template-Typ | Pflichtfelder (Auszug) |
|---|---|---|---|
| Zweckbestimmung und klinischer Nutzen | ANNEX_II_A_1 | `INTENDED_PURPOSE` | indications, userGroup, patientGroup, useEnvironment, clinicalBenefit, clinicalEvaluationRef |
| Produktbeschreibung, Materialien und Varianten | ANNEX_II_A_2 | `PRODUCT_DESCRIPTION` | productFamily, variantLogic, materials, contactType, biocompatibilityRef |
| UDI-DI / Basic-UDI-DI-Zuordnung | ANNEX_II_A_3 | `UDI_MAPPING` | basicUdiDi, issuingEntity, variantMapping, formatValidated |
| Klassifizierung und Begründung der Regelanwendung | ANNEX_II_A_4 | `CLASSIFICATION_RULE` | mdrClass, classificationRule, justificationMd, referenceLinks |
| Funktionsprinzip und Leistungsansprüche | ANNEX_II_A_5 | `OPERATING_PRINCIPLE` | operatingPrinciple, performanceParameters, acceptanceCriteria, verificationValidationRef |
| Vorgängergenerationen / ähnliche Produkte | ANNEX_II_A_6 | `PREVIOUS_GENERATIONS` | comparisonTable, differences, equivalenceRationale, pmsPmcfClinicLinks |

## 2) DB-/Schema-Vorschlag inkl. Migration

- `td_node_template`
  - `id`, `td_section`, `td_node`, `template_type`, `template_version`, `fields_json`, `created_at`, `updated_at`
- `td_node_response`
  - `id`, `td_id`, `td_node`, `template_version`, `status`, `owner_user_id`, `due_at`, `field_responses_json`, `generated_markdown`, `legacy_answer_markdown`, `legacy_rationale_markdown`, `updated_at`, `updated_by`
- `td_node_reference`
  - `id`, `td_node_response_id`, `type`, `ref_id`, `label`, `url`, `meta_json`, `is_auto`, `created_at`

### Migrationsmapping (Bestandsschutz)
- Alt `answerMarkdown` → `field_responses_json.md_text_main`
- Alt `rationaleMarkdown` → `field_responses_json.md_text_rationale`
- Bestehende Query-Links → `td_node_reference[]`
- `template_version` wird je bestehender Antwort gesetzt; ohne Treffer Fallback `1`.

## 3) API-Routen

- `GET /api/td/templates?sectionTemplateKey=ANNEX_II_A` → liefert Template-Definitionen je Unterpunkt.
- `GET /api/td/:id/queries` → liefert Responses inkl. `nodeTemplate`, `fieldResponses`, `validation`.
- `PUT /api/td/queries/:answerId` → speichert Feldantworten + Legacy-Felder; setzt Auto-Text/Auto-Referenzen.
- `POST /api/td/queries/:answerId/links` → manuelle Referenzen.
- `GET /api/reference-resolver/legal?type=MDR_CLASSIFICATION_RULE&value=11` → zentrale EU-Lex/MDR-Auflösung.

## 4) Flutter Form-Renderer Architektur

- `TdQueryTemplate.nodeTemplate.fields[]` steuert Rendering.
- Feldtypen im Renderer:
  - `select_single` → Dropdown
  - `select_multi` → Chips/kommagetrennte Multi-Eingabe
  - `md_text` / `generated_md` → Markdown-Textfelder
  - `link_ref` → Referenzliste/Link-Chips
- Status-Logik:
  - „Abgeschlossen“ nur bei erfüllter `validation.canComplete` (Pflichtfelder + Referenzen).
  - Badge „Nachweis/Link fehlt“ wenn `missingReferences` oder Pflichtfelder fehlen.

## 5) Seed-Datenstruktur MDR-Regeln (1–22) + Resolver

- Seed: `MDR_CLASSIFICATION_RULES[]` mit
  - `rule_no`, `title_short`, `mdr_ref`, `eu_lex_link`, `rule_text_excerpt`
- Resolver:
  - `resolveMdrClassificationRule(ruleNo)`
  - `buildMdrRuleReference(ruleNo)` für Auto-Link in TD (Meta `auto: true`)
- Reuse:
  - GSPR nutzt denselben zentralen MDR-EU-Lex-Permalink über `legalRefService`.

## 6) Umsetzungsreihenfolge (ToDos)

1. Templates/Resolver in Backend finalisieren und versionieren.
2. Migration `answerMarkdown/rationaleMarkdown/links` nach `fieldResponses` automatisiert fahren.
3. Flutter-Renderer für `nodeTemplate.fields` erweitern (done für Struktur-Unterpunkte A.1–A.6).
4. Validierung serverseitig als Single Source of Truth lassen und UI nur anzeigen.
5. Smoke-Tests auf Bestandsdaten + Klassifizierungs-Autolink.
