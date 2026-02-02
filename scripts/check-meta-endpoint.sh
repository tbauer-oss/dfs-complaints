#!/usr/bin/env bash
set -euo pipefail

BASE_URL=${1:-https://dfs-complaints-backend.vercel.app}
ORIGIN=${2:-https://dfs-complaints-web.vercel.app}

OPTIONS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "$BASE_URL/api/meta" \
  -H "Origin: $ORIGIN" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: authorization,content-type")

if [[ "$OPTIONS_STATUS" -lt 200 || "$OPTIONS_STATUS" -ge 300 ]]; then
  echo "OPTIONS /api/meta failed with status $OPTIONS_STATUS" >&2
  exit 1
fi

GET_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$BASE_URL/api/meta" \
  -H "Origin: $ORIGIN")
GET_BODY=$(echo "$GET_RESPONSE" | head -n 1)
GET_STATUS=$(echo "$GET_RESPONSE" | tail -n 1)

if [[ "$GET_STATUS" -lt 200 || "$GET_STATUS" -ge 300 ]]; then
  echo "GET /api/meta failed with status $GET_STATUS" >&2
  exit 1
fi

if [[ -z "$GET_BODY" ]]; then
  echo "GET /api/meta returned empty body" >&2
  exit 1
fi

echo "OPTIONS /api/meta: $OPTIONS_STATUS"
echo "GET /api/meta: $GET_STATUS"
