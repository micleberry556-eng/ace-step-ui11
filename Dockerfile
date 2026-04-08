# ACE-Step UI Frontend
# Multi-stage build: Vite/React build -> nginx for static serving + API proxy

# --- Build stage ---
FROM node:22-alpine AS builder

WORKDIR /app

# Copy package files and install dependencies
COPY package.json package-lock.json ./
RUN npm ci

# Copy all frontend source files needed for the Vite build
COPY index.html index.tsx tsconfig.json vite.config.ts global.d.ts vite-env.d.ts types.ts App.tsx ./
COPY components/ ./components/
COPY context/ ./context/
COPY services/ ./services/
COPY data/ ./data/
COPY i18n/ ./i18n/

# Build the production bundle
RUN npm run build

# --- Production stage ---
FROM nginx:1.27-alpine

# Copy built static files
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
