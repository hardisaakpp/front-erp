FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# `VITE_APP_BASE_PATH`, `VITE_*` en produccion: proceso en build y tiene prioridad sobre archivos ignorados por git que no llegan en el contexto Docker.
# Por defecto subruta compartida con legacy (codigoqr); raíz del host: --build-arg VITE_APP_BASE_PATH=/
ARG VITE_APP_BASE_PATH=/articulo-scaner/
ENV VITE_APP_BASE_PATH=${VITE_APP_BASE_PATH}

RUN npm run build

FROM nginx:1.27-alpine AS runtime
COPY deploy/nginx/scnexus-spa.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
