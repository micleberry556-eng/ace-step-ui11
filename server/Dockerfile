# ACE-Step UI Backend
# Node.js server with Express, SQLite, and audio file management

FROM node:22-alpine AS builder

WORKDIR /app

# Install build dependencies for better-sqlite3 (native module)
RUN apk add --no-cache python3 make g++

# Copy package files and install dependencies
COPY package.json package-lock.json ./
RUN npm ci

# Copy source code and build
COPY tsconfig.json ./
COPY src/ ./src/

RUN npm run build

# --- Production stage ---
FROM node:22-alpine

WORKDIR /app

# Install runtime dependencies for better-sqlite3
RUN apk add --no-cache python3 make g++

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && apk del python3 make g++

# Copy built output
COPY --from=builder /app/dist ./dist

# Copy static assets served by the backend
COPY audio-editor/ ./audio-editor/
COPY public/ ./public/

# Create data and audio directories
RUN mkdir -p /app/data /app/public/audio /app/public/audio/reference-tracks

# Environment defaults
ENV NODE_ENV=production
ENV PORT=3001
ENV DATABASE_PATH=/app/data/acestep.db
ENV AUDIO_DIR=/app/public/audio
ENV FRONTEND_URL=http://localhost:80

EXPOSE 3001

CMD ["node", "dist/index.js"]
