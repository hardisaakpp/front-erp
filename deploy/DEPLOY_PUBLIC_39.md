# Deploy en servidor publico 192.168.2.39

Este proyecto se despliega en `192.168.2.39` y **no reemplaza** el entorno actual en `192.168.2.153`.

## 1) Build y ejecucion con Docker

```bash
docker compose up -d --build
```

Esto levanta el frontend en `localhost:8081` dentro del servidor (puerto por defecto actual).

## 2) Nginx host (servidor 192.168.2.39)

Usar como base:

- `deploy/nginx/scnexus-public-39.conf.example`

Copiar a `/etc/nginx/sites-available/` (o ruta equivalente), habilitar el sitio y recargar Nginx.

## 3) Validaciones

1. Abrir `http://192.168.2.39:3002`.
2. Probar una ruta directa de SPA (ejemplo: `/dashboard`) y confirmar que no da 404.
3. Revisar en devtools que los assets JS/CSS cargan correctamente.

## 4) Regla de separacion de entornos

- No modificar la configuracion productiva de `192.168.2.153` para este despliegue.
- Mantener archivos de Nginx, puertos y rutas de publicacion diferenciados entre ambos servidores.
