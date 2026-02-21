# Regulatory Sync (MDR + GSPR cache)

## Environment

Required environment variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` (server only)
- `SUPABASE_ANON_KEY` (client)
- `REGULATORY_SYNC_TOKEN_SECRET`

## Migration

```bash
supabase db push
```

## Local development

```bash
vercel dev
cd flutter_web && flutter run -d chrome
```

## Manual test checklist

1. Initial sync populates MDR versions + sections in `legal_versions` / `legal_sections`.
2. Re-running sync without an upstream change returns `has_update=false`.
3. Applying a sync creates rows in `legal_changes` and `legal_section_changes` and advances `legal_documents.current_version_id`.
4. GSPR impact detection returns requirements linked through `gspr_links`.

## Snapshot cache keys (Flutter persistent cache)

TD und GSPR nutzen einen cache-first Ansatz über persistente JSON-Snapshots (Web LocalStorage) und Hintergrund-Refresh.

- `td:structure:{tdId}:{regVersionHash}:{locale}`
- `td:section:{tdId}:{sectionKey}:{regVersionHash}:{locale}`
- `gspr:overview:{tdId}:{regVersionHash}:{locale}`
- `gspr:req:{tdId}:{gsprNo}:{regVersionHash}:{locale}`

Die Invalidierung ist implizit über `regVersionHash`/`versionLabel` gelöst: ändert sich die regulatorische Version, entstehen neue Keys und alte Snapshots werden nicht mehr gelesen.
