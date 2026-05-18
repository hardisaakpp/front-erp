FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# `VITE_APP_BASE_PATH`, `VITE_*` en produccion: proceso en build y tiene prioridad sobre archivos ignorados por git que no llegan en el contexto Docker.
# Por defecto subruta compartida con legacy (codigoqr); raíz del host: --build-arg VITE_APP_BASE_PATH=/
ARG VITE_APP_BASE_PATH=/scnexus-front/
ENV VITE_APP_BASE_PATH=${VITE_APP_BASE_PATH}

RUN npm run build

FROM nginx:1.27-alpine AS runtime
# Upstream del microservicio .NET de scan (GET /api/v1/warehouses, etc.).
# Default: srv-mabuiosapi (192.168.2.153:8080) → contenedor scnexus-articulo-api.
# Otro despliegue: docker compose build --build-arg SCAN_API_UPSTREAM=http://HOST:PUERTO
ARG SCAN_API_UPSTREAM=http://192.168.2.153:8080
# API Promoción Sobres en el host (scnexus-validacionCI, puerto 8083 por defecto).
ARG PROMOCION_SOBRES_API_UPSTREAM=http://host.docker.internal:8083
COPY deploy/nginx/scnexus-spa.conf /tmp/scnexus-spa.conf
RUN sed -e "s|__SCAN_API_UPSTREAM__|${SCAN_API_UPSTREAM}|g" \
        -e "s|__PROMOCION_SOBRES_API_UPSTREAM__|${PROMOCION_SOBRES_API_UPSTREAM}|g" \
        /tmp/scnexus-spa.conf > /etc/nginx/conf.d/default.conf \
    && rm /tmp/scnexus-spa.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
