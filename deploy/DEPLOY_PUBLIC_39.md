# Despliegue en servidor publico 192.168.2.39 (runbook)

Este documento resume el procedimiento validado para publicar el frontend SCNexus en el servidor **`192.168.2.39`**. Ese entorno es **independiente** del de produccion actual en **`192.168.2.153`** (no se reemplaza el sitio existente alli).

## Arquitectura resumida

```text
Cliente (navegador)
    -> http://192.168.2.39:3002
        -> Apache (reverse proxy)
            -> http://127.0.0.1:8081
                -> Contenedor Docker (imagen scnexus-front)
                    -> Nginx interno sirve dist (SPA + proxies API en scnexus-spa.conf)
```

- **Puerto publico:** `3002` (Apache).
- **Puerto interno del contenedor en el host:** `8081` -> `80` dentro del contenedor (ver `docker-compose.yml`, variable `SCNEXUS_FRONT_PORT` por defecto `8081`).
- **Codigo en servidor:** recomendado bajo `/storage/scnexus-front`.
- **Rama:** `frontend-dockerizado` (o la rama acordada para releases).

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

## 4) Apache: exponer el sitio en el puerto 3002

### 4.1 Habilitar modulos

```bash
a2enmod proxy proxy_http headers
systemctl restart apache2
```

(`restart` asegura que carguen modulos nuevos; luego se puede usar `reload` para cambios de config.)

### 4.2 Escuchar en 3002

Si `grep -R "Listen " /etc/apache2/` no muestra `3002`, anadir en `/etc/apache2/ports.conf`:

```apache
Listen 3002
```

### 4.3 VirtualHost

Crear `/etc/apache2/sites-available/scnexus-front-public.conf`:

```apache
<VirtualHost *:3002>
    ServerName 192.168.2.39

    ProxyPreserveHost On
    ProxyRequests Off

    ProxyPass        / http://127.0.0.1:8081/
    ProxyPassReverse / http://127.0.0.1:8081/

    RequestHeader set X-Forwarded-Proto "http"
</VirtualHost>
```

Habilitar y validar:

```bash
a2ensite scnexus-front-public.conf
apachectl configtest
systemctl reload apache2
```

### 4.4 Aviso AH00558 (opcional, cosmético)

Si aparece `Could not reliably determine the server's fully qualified domain name`, anadir en `/etc/apache2/apache2.conf` (o conf habilitado):

```apache
ServerName localhost
```

y `systemctl reload apache2`.

---

## 5) Firewall

Si usas UFW:

```bash
ufw allow 3002/tcp
ufw status
```

---

## 6) Validaciones finales

En el servidor:

```bash
curl -I http://127.0.0.1:3002
ss -ltnp | grep ':3002 '
```

Desde la red interna:

- Abrir `http://192.168.2.39:3002`.
- Probar login.
- Probar ruta SPA directa (por ejemplo `/dashboard`) sin 404.
- Revisar en DevTools que `/api/*`, `/scan-api/*`, etc. respondan JSON (no HTML del index).

---

## 7) Actualizar despliegue

```bash
cd /storage/scnexus-front
git pull
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
cd /storage/scnexus-front && git pull && docker compose up -d --build
curl -I http://127.0.0.1:8081
curl -I http://127.0.0.1:3002
```
