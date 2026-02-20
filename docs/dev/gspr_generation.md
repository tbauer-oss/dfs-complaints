# GSPR Annex I generation

## Source
The generator fetches the consolidated German MDR Annex I text from:

- Supabase regulatory cache snapshot (mdr-2017-745)

Only the content between the following markers is extracted (inclusive start, exclusive end):

- `ANHANG I\nGRUNDLEGENDE SICHERHEITS- UND LEISTUNGSANFORDERUNGEN`
- `ANHANG II\nTECHNISCHE DOKUMENTATION` (excluded; marks the end)

## Atomic items
"Atomic" means every requirement is separated into an independently assessable clause:

- Each numbered requirement and decimal subsection (e.g. `10.4`, `10.4.1`) is its own item.
- Each letter list entry (`a)`, `b)`, `aa)`) is its own item.
- Each dash bullet (`—`) is its own item.

Example IDs:

- `1`
- `3.a`
- `10.4.1`
- `10.4.1.a`
- `23.4.k`
- `23.4.k.--1`

## Regeneration

Run the generator from the repo root:

```bash
npm run generate:gspr
```

The generator will:

- Fetch the source HTML.
- Extract the Annex I section only.
- Parse into atomic items with canonical IDs.
- Write the generated module to `src/compliance/gspr/gspr_items.generated.ts`.
- Write the server-side module to `api/_lib/gspr_items.generated.js`.

## Failure rules

The generator fails fast if:

- The Annex I/II markers cannot be found in the source text.
- The generated item count is suspiciously low (fails if `< 200`).

It also logs summary counts per chapter and per level for quick validation.
