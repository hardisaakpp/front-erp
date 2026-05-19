#!/usr/bin/env bash
# Uso en srv-mabletest (192.168.2.39):
#   cd /storage/scnexus-front && bash deploy/server-39-redeploy.sh
set -euo pipefail

cd "$(dirname "$0")/.."

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
  cat > .env <<'EOF'
VITE_APP_BASE_PATH=/scnexus-front/
PROMOCION_SOBRES_API_UPSTREAM=http://host.docker.internal:8083
EOF
  echo "Creado .env"
fi

echo "==> Build y arranque"
docker compose down || true
docker compose build --no-cache
docker compose up -d

echo "==> Verificación contenedor"
docker ps --filter name=scnexus-front-public --format 'table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}'
COUNT=$(docker exec scnexus-front-public grep -c 'promocion-sobres-api' /etc/nginx/conf.d/default.conf || true)
echo "location promocion-sobres-api en nginx: ${COUNT} (debe ser >= 1)"

echo "==> Proxy promoción sobres (debe ser JSON o 401, no text/html)"
curl -sI "http://127.0.0.1:8081/promocion-sobres-api/api/promocion-sobres/v1/diagnostics/database" | head -5

echo "==> API en host :8083 (opcional si corre scnexus-validacionCI aquí)"
curl -sS -m 3 "http://127.0.0.1:8083/health/live" && echo || echo "AVISO: sin respuesta en :8083 — levanta el API o ajusta PROMOCION_SOBRES_API_UPSTREAM en .env"
