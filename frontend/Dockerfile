# The SPA served by nginx, for Cloud Run. Build with frontend/ as the context:
#   docker build -t li-frontend \
#     --build-arg VITE_API_BASE=https://<api_hostname> \
#     --build-arg VITE_GOOGLE_CLIENT_ID=<id>.apps.googleusercontent.com frontend
# Both values are baked in at build time; neither is secret.
FROM node:22.22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_API_BASE=""
ARG VITE_GOOGLE_CLIENT_ID=""
ENV VITE_API_BASE=$VITE_API_BASE \
    VITE_GOOGLE_CLIENT_ID=$VITE_GOOGLE_CLIENT_ID \
    VITE_DEV_AUTH=0
RUN npm run build
# The CSP's connect-src must name the API origin.
RUN sed -i "s|__API_ORIGIN__|${VITE_API_BASE}|" nginx/security-headers.conf

FROM nginxinc/nginx-unprivileged:1.30.6-alpine
COPY --from=build /app/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/nginx/security-headers.conf /etc/nginx/security-headers.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
