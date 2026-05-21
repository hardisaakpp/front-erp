#!/usr/bin/env bash
# Uso en srv-mabletest (192.168.2.39):
#   cd /storage/scnexus-front && bash deploy/server-39-redeploy.sh
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_TEMPLATE=".env.docker.39.example"

echo "==> Git (requiere commit >= 04edbce en frontend-dockerizado)"
git fetch origin
git checkout frontend-dockerizado
git pull --ff-only origin frontend-dockerizado
git rev-parse --short HEAD

if ! grep -q 'mba3-nexus_edge' docker-compose.yml 2>/dev/null; then
  echo "OK: docker-compose.yml sin red MBA3 externa"
else
  echo "ERROR: docker-compose.yml aún declara mba3-nexus_edge. Haz git pull hasta 04edbce o posterior."
  exit 1
fi

if [[ ! -f .env ]]; then
  if [[ ! -f "$ENV_TEMPLATE" ]]; then
    echo "ERROR: falta $ENV_TEMPLATE — git pull e intentá de nuevo."
    exit 1
  fi
  cp "$ENV_TEMPLATE" .env
  echo "Creado .env desde $ENV_TEMPLATE"
else
  echo "Usando .env existente."
  if ! grep -q '^MBA3_UPSTREAM=' .env; then
    echo "AVISO: .env sin MBA3_UPSTREAM — /api/Auth/me puede dar 504."
    echo "       Copiá MBA3_UPSTREAM y SCAN_API_UPSTREAM desde $ENV_TEMPLATE"
  fi
fi

echo "==> Upstreams en .env (se hornean al build)"
grep -E '^(MBA3|CORE|SCAN|PROMOCION_SOBRES)_UPSTREAM=' .env || true

echo "==> Build y arranque (limpia nombre antiguo scnexus-front-public si existe)"
docker stop scnexus-front-public 2>/dev/null || true
docker rm scnexus-front-public 2>/dev/null || true
docker compose down || true
docker compose build --no-cache
docker compose up -d

echo "==> Verificación contenedor"
docker ps --filter name=scnexus-front --format 'table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}'
docker exec scnexus-front grep -E 'location = /api/Auth/me|proxy_pass' /etc/nginx/conf.d/default.conf | head -4

echo "==> Auth/me (debe ser 401 JSON, no 504 HTML)"
curl -sI -m 15 "http://127.0.0.1:8081/api/Auth/me" | head -5

echo "==> Proxy promoción sobres (debe ser 200 Healthy en <15s, no 504 HTML)"
curl -sI -m 15 "http://127.0.0.1:8081/promocion-sobres-api/health/ready" | head -5
curl -sS -m 15 -o /dev/null -w "promocion-sobres via 8081: HTTP %{http_code} en %{time_total}s\n" \
  "http://127.0.0.1:8081/promocion-sobres-api/health/ready" || true

echo "==> API directo en srv-mabuiosapi :8083 (referencia; el front usa PROMOCION_SOBRES_UPSTREAM)"
curl -sS -m 5 -o /dev/null -w "API directo :8083: HTTP %{http_code} en %{time_total}s\n" \
  "http://127.0.0.1:8083/health/live" 2>/dev/null || echo "AVISO: sin :8083 en este host — normal en .39; el upstream debe ser la IP del API (p. ej. 192.168.2.153:8083)"
