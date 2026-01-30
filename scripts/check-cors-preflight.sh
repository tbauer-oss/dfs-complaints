#!/usr/bin/env bash
set -euo pipefail

curl -i -X OPTIONS https://dfs-complaints-backend.vercel.app/api/training/dashboard-metrics \
  -H "Origin: https://dfs-complaints-web.vercel.app" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: authorization,content-type"
