# Despliegue en servidor publico 192.168.2.39 (runbook)

Este documento deja el procedimiento final validado para publicar SCNexus en `192.168.2.39` **sin romper** los sitios legacy ya operativos en el mismo dominio.

## Resultado objetivo (validado)

- Mantener operativos:
  - `https://codigoqr.mabelgroup.com.ec/sc24/`
  - `https://codigoqr.mabelgroup.com.ec/checkin/mns_check.php`
- Publicar SCNexus en subruta dedicada (`/scnexus-front/`). Las URLs antiguas bajo `/articulo-scaner/` redirigen **301** al nuevo prefijo (Nginx en contenedor y/o reglas en Apache; ver `deploy/nginx/scnexus-spa.conf` y `deploy/apache/sitio.conf.reference`).
- Evitar capturar todo el dominio con `ProxyPass /` desde un vhost nuevo.

## Arquitectura final recomendada

```text
Cliente (navegador)
    -> https://codigoqr.mabelgroup.com.ec
        -> Apache vhost existente (sitio.conf, DocumentRoot /storage)
            -> /sc24/*      (legacy en /storage/sc24)
            -> /checkin/*   (legacy en /storage/checkin)
            -> /scnexus-front/*  (proxy al contenedor SCNexus en 127.0.0.1:8081)
```

- **Dominio publico:** `codigoqr.mabelgroup.com.ec`.
- **Puertos publicos:** `80/443` (Apache).
- **Contenedor SCNexus:** `127.0.0.1:8081 -> 80`.
- **Vhost base recomendado:** `sitio.conf` (no crear otro vhost para el mismo dominio salvo necesidad muy justificada).

---

## Requisitos previos en el servidor

- Docker Engine funcionando (`docker version`).
- Acceso **SSH** y permisos **root** (o sudo) para Apache y Docker.
- **Apache2** ya en uso en el servidor (en este entorno el puerto **80** suele estar ocupado por Apache; por eso se publica el nuevo sitio en **3002**).
- Repositorio clonable por **SSH** (clave del servidor registrada en la cuenta GitHub con acceso al repo).

---

## 1) Clonar el repositorio

```bash
mkdir -p /storage
cd /storage
git clone git@github.com:<owner>/<repo>.git scnexus-front
cd scnexus-front
git checkout frontend-dockerizado
git pull
```

Si `git clone` HTTPS pide usuario/contrasena, usar URL **SSH** como arriba. Si aparece `Repository not found`, revisar permisos del usuario GitHub y la URL exacta del repo.

Comprobar archivos Docker:

```bash
ls -la Dockerfile docker-compose.yml
```

---

## 2) Docker Compose v2 (plugin)

Si `docker compose` no existe y aparece `docker: 'compose' is not a docker command`, instalar el plugin oficial desde el repositorio de Docker (ejemplo validado en Ubuntu **oracular**):

```bash
apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-compose-plugin
docker compose version
```

Si tu distro no tiene suite en `download.docker.com` para ese `VERSION_CODENAME`, usar la suite **LTS** mas cercana (por ejemplo `noble`) en la linea `deb ...` segun documentacion Docker.

**Alternativa rapida sin plugin:** `docker build -t scnexus-front:latest .` y `docker run -d --name scnexus-front --restart unless-stopped -p 8081:80 scnexus-front:latest`.

---

## 3) Levantar el frontend con Compose

### Base path `/scnexus-front/` en el mismo dominio (legacy + SPA)

`.env.production` esta **en `.gitignore`**: despues de `git pull` el servidor suele construir sin esas vars. El Dockerfile ahora admite **`VITE_APP_BASE_PATH` como build-arg** desde `docker-compose.yml`.

Creá en **`/storage/scnexus-front/.env`** (junto al `compose`, no commiteado) al menos:

```env
VITE_APP_BASE_PATH=/scnexus-front/
```

Opcional: copiá el resto de variables de `.env.production.example` ahí mismo o mantené un `.env.production` solo en servidor; el build-arg vuelve a exportar **`VITE_APP_BASE_PATH`** dentro de la imagen antes de `npm run build`.

Construcción y arranque (recomendado forzar rebuild del stage de build tras cambiar base path):

```bash
cd /storage/scnexus-front
docker compose build --no-cache
docker compose up -d
docker compose ps
```

Comprobar dentro del contenedor que el bundle salió bajo subruta (debe existir la carpeta y los `src`/ `href` con `/scnexus-front/assets/`):

```bash
docker exec scnexus-front ls -la /usr/share/nginx/html/
# Vite deposita index.html y assets/ en la raíz; el prefijo /scnexus-front/ solo va en URLs del HTML.
docker exec scnexus-front grep -Eo 'src="/scnexus-front/[^"]+"' /usr/share/nginx/html/index.html | head
```

Si el HTML carga pero **`/scnexus-front/assets/*.js` devuelve 404**: (1) forzá `docker compose build --no-cache` (evita capas cacheadas de `npm run build` desalineadas con el `index.html`); (2) comprobá que un `src` del `grep` anterior exista en disco: `docker exec scnexus-front ls /usr/share/nginx/html/assets/ | head`; (3) en Apache usá `ProxyPass /scnexus-front/ http://127.0.0.1:8081/scnexus-front/` **con barras finales** (ver `deploy/apache/sitio.conf.reference`).

### Despliegue en raíz del contenedor (sin subruta)

Si no necesitás subruta, omití `VITE_APP_BASE_PATH` en `.env` o usá `/` explicito (`VITE_APP_BASE_PATH=/`).

```bash
cd /storage/scnexus-front
docker compose up -d --build
docker compose ps
```

Validacion local en el servidor:

```bash
curl -I http://127.0.0.1:8081
```

Se espera `HTTP/1.1 200 OK` (u otro 2xx) y cabeceras coherentes con Nginx del contenedor.

**Puerto host alternativo** (si `8081` esta ocupado):

```bash
SCNEXUS_FRONT_PORT=8090 docker compose up -d --build
```

(Ajustar entonces el `ProxyPass` de Apache al mismo puerto.)

---

## 4) Apache: integrar SCNexus sin romper legacy

> Procedimiento final: editar el vhost existente `sitio.conf` para mantener `sc24`/`checkin` y agregar solo `/scnexus-front/` al contenedor.

### 4.1 Habilitar modulos

```bash
a2enmod proxy proxy_http headers rewrite ssl
systemctl restart apache2
```

(`restart` asegura que carguen modulos nuevos; luego se puede usar `reload` para cambios de config.)

### 4.2 Escuchar en 80/443

Si `grep -R "Listen " /etc/apache2/` no muestra `80` y `443`, anadir en `/etc/apache2/ports.conf`:

```apache
Listen 80
Listen 443
```

### 4.3 Editar `sitio.conf` (vhost existente)

Abrir:

```bash
sudo nano /etc/apache2/sites-available/sitio.conf
```

En el bloque `<VirtualHost *:443>`, mantener `DocumentRoot /storage` (legacy) y agregar:

```apache
# --- SCNexus bajo subruta ---
ProxyPreserveHost On
ProxyRequests Off

# Legacy /articulo-scaner/ → /scnexus-front/ (301). scan-api bajo la ruta antigua va a /scan-api/.
RedirectMatch permanent ^/articulo-scaner/scan-api/(.*)$ /scan-api/$1
RedirectMatch permanent ^/articulo-scaner/(.*)$ /scnexus-front/$1
RedirectMatch 302 ^/articulo-scaner$ /scnexus-front/

# Normalizar sin slash final en la nueva subruta
RedirectMatch 302 ^/scnexus-front$ /scnexus-front/

# Si en el navegador se usa /scnexus-front/scan-api/... (URL incorrecta del front).
RedirectMatch permanent ^/scnexus-front/scan-api/(.*)$ /scan-api/$1

# Enviar solo la subruta al contenedor (no usar ProxyPass /)
ProxyPass        /scnexus-front/ http://127.0.0.1:8081/scnexus-front/
ProxyPassReverse /scnexus-front/ http://127.0.0.1:8081/scnexus-front/

# Mismas APIs que el front pide en el dominio raíz (obligatorio para Articulo Scaner).
# El Nginx del contenedor (`deploy/nginx/scnexus-spa.conf`) hace el proxy final a los backends.
ProxyPass        /api/             http://127.0.0.1:8081/api/
ProxyPassReverse /api/             http://127.0.0.1:8081/api/
ProxyPass        /scan-api/        http://127.0.0.1:8081/scan-api/
ProxyPassReverse /scan-api/        http://127.0.0.1:8081/scan-api/
```

Aplicar:

```bash
sudo apachectl configtest
sudo systemctl reload apache2
```

### 4.4 Referencia del vhost actual

Para dejar trazabilidad en el repo:

- Referencia capturada: `deploy/apache/sitio.conf.reference`
- Plantilla standalone (vhost dedicado): `deploy/apache/scnexus-public-39-https.conf.example`

Para este servidor, la opción preferida es la primera (coexistencia en `sitio.conf`).

### 4.5 Certificado SSL (reusar wildcard existente)

Si el servidor ya tiene certificado corporativo (p. ej. wildcard `*.mabelgroup.com.ec`), usar rutas como:

```apache
SSLCertificateFile /etc/ssl/certs/server.crt
SSLCertificateKeyFile /etc/ssl/private/server.key
SSLCertificateChainFile /etc/ssl/certs/bundle.crt
```

Puedes validar que el sitio activo actual (`sitio.conf`) usa esas rutas antes de habilitar el nuevo vhost.

### 4.6 Let's Encrypt (alternativa, solo si no existe certificado corporativo)

```bash
apt-get install -y certbot python3-certbot-apache
certbot --apache -d codigoqr.mabelgroup.com.ec
```

Luego validar:

```bash
apachectl configtest
systemctl reload apache2
```

### 4.7 Aviso AH00558 (opcional, cosmético)

Si aparece `Could not reliably determine the server's fully qualified domain name`, anadir en `/etc/apache2/apache2.conf` (o conf habilitado):

```apache
ServerName localhost
```

y `systemctl reload apache2`.

---

## 5) Firewall

Si usas UFW:

```bash
ufw allow 80/tcp
ufw allow 443/tcp
ufw status
```

---

## 6) Validaciones finales

En el servidor:

```bash
curl -I http://127.0.0.1:8081
curl -sI "http://127.0.0.1:8081/scan-api/api/v1/warehouses"
curl -I https://codigoqr.mabelgroup.com.ec
ss -ltnp | grep -E ':80 |:443 '
```

La segunda línea debe devolver **`application/json`** (p. ej. 401 sin token) o listado en **200**, no **`text/html`**, **404** vacío ni **504**. El upstream del scan se define al **build** de la imagen con **`SCAN_API_UPSTREAM`** (por defecto `http://192.168.2.153:8080`, contenedor `scnexus-articulo-api` en `srv-mabuiosapi`). Si cambia de host/puerto, en el directorio del compose (p. ej. `/storage/scnexus-front`), crear o editar `.env` junto a `docker-compose.yml`:

```bash
SCAN_API_UPSTREAM=http://192.168.2.153:8080
```

Luego `docker compose build --no-cache && docker compose up -d`. Sin `docker compose`, usar `docker build --build-arg SCAN_API_UPSTREAM=http://HOST:PUERTO -t scnexus-front:latest .`

Desde cualquier cliente con acceso DNS:

- Abrir `https://codigoqr.mabelgroup.com.ec`.
- Probar legacy:
  - `https://codigoqr.mabelgroup.com.ec/sc24/`
  - `https://codigoqr.mabelgroup.com.ec/checkin/mns_check.php`
- Probar SCNexus:
  - `https://codigoqr.mabelgroup.com.ec/scnexus-front/`
- Revisar en DevTools que SCNexus consulte APIs correctamente (`/api/*`, `/scan-api/*`, etc.).

---

## 7) Actualizar despliegue

```bash
cd /storage/scnexus-front
git fetch origin
git checkout frontend-dockerizado
git pull --ff-only origin frontend-dockerizado
docker compose up -d --build
```

Logs:

```bash
docker compose logs -f scnexus-front
tail -f /var/log/apache2/error.log
```

---

## 8) Rollback rapido (codigo)

```bash
cd /storage/scnexus-front
git log --oneline -n 10
git checkout <commit_estable>
docker compose up -d --build
```

---

## 9) Notas y referencias

### Ajuste obligatorio de build para subruta

SCNexus debe construirse con base path de subruta para convivir en el mismo dominio legacy:

```env
VITE_APP_BASE_PATH=/scnexus-front/
```

Esta variable ya está soportada en:

- `vite.config.ts` (propiedad `base`)
- `src/router/index.ts` (`createWebHistory(appBasePath)`)

Sin ese ajuste, la SPA intentará cargar assets desde `/assets/*` (raíz) y puede colisionar con sitios legacy.

### Lección aprendida sobre rutas legacy

- Alias de Vue Router como `/checkin` o `/checkin/index.php` para apuntar al módulo escáner (`src/modules/articulo-scaner`) reemplazan el flujo PHP legacy.
- Para conservar `checkin` histórico, no usar esos alias ni `ProxyPass /` global que capture todo el dominio.

### Lección aprendida sobre remotos Git

Se detectó desalineación por usar remotos distintos entre local y servidor:

- Local: `https://github.com/alextz111/scnexus-front.git`
- Servidor: `git@github-cortiz:hardisaakpp/scnexus-front.git`

Validar siempre antes de desplegar:

```bash
git remote -v
git rev-parse --short HEAD
git show --name-only --oneline HEAD
```

### Nginx en el contenedor vs Apache en el host

El `Dockerfile` copia `deploy/nginx/scnexus-spa.conf` al contenedor. Ese archivo incluye proxies a backends internos (IPs de red corporativa). Si en `39` las APIs no son alcanzables desde la red Docker, apareceran `502` en ciertas rutas: hay que alinear IPs/hostnames con el entorno real o replicar en Apache reglas similares a `deploy/nginx/scnexus.conf.example` **antes** del proxy al frontend.

### Referencia Nginx-only (si en el futuro no se usa Apache en 39)

Ejemplo de reverse proxy solo Nginx: `deploy/nginx/scnexus-public-39.conf.example` (proxy a `127.0.0.1:8081`). En el despliegue actual con Apache en puerto 80, **no** hace falta Nginx adicional en el host para este sitio.

### Separacion de entornos 153 vs 39

- No modificar la configuracion que sirve el entorno productivo en `192.168.2.153` para este despliegue.
- Mantener puertos, virtual hosts y rutas de publicacion distintos entre servidores.

### APT: avisos duplicados en sources

Los avisos `Packages ... configurado varias veces` no impidieron el despliegue descrito; conviene limpiar `/etc/apt/sources.list` vs `ubuntu.sources` cuando haya ventana de mantenimiento.

---

## 10) Resumen de comandos (copiar despues de install limpio)

```bash
cd /storage/scnexus-front
git fetch origin
git checkout frontend-dockerizado
git pull --ff-only origin frontend-dockerizado
docker compose up -d --build
curl -I http://127.0.0.1:8081
curl -I https://codigoqr.mabelgroup.com.ec
```
