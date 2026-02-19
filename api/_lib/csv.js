export function parseCsv(csvText = '', delimiter = ',') {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  const text = String(csvText || '').replace(/^\uFEFF/, '');

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];

    if (char === '"') {
      if (inQuotes && text[i + 1] === '"') {
        field += '"';
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (!inQuotes && char === delimiter) {
      row.push(field);
      field = '';
      continue;
    }

    if (!inQuotes && (char === '\n' || char === '\r')) {
      if (char === '\r' && text[i + 1] === '\n') i += 1;
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
      continue;
    }

    field += char;
  }

  row.push(field);
  if (row.some((cell) => String(cell || '').trim().length > 0)) rows.push(row);
  return rows;
}

export function detectCsvDelimiter(headerLine = '') {
  const comma = (headerLine.match(/,/g) || []).length;
  const semicolon = (headerLine.match(/;/g) || []).length;
  return semicolon > comma ? ';' : ',';
}

export function parseCsvObjects(csvText = '') {
  const lines = String(csvText || '').split(/\r?\n/);
  const headerLine = lines.find((line) => String(line || '').trim().length > 0) || '';
  if (!headerLine) return [];

  const delimiter = detectCsvDelimiter(headerLine);
  const rows = parseCsv(csvText, delimiter);
  if (!rows.length) return [];

  const headers = rows[0].map((cell) => String(cell || '').trim());
  return rows.slice(1)
    .filter((values) => values.some((cell) => String(cell || '').trim().length > 0))
    .map((values) => {
      const item = {};
      for (let i = 0; i < headers.length; i += 1) {
        const key = String(headers[i] || '').trim();
        if (!key) continue;
        item[key] = String(values[i] ?? '').trim();
      }
      return item;
    });
}
