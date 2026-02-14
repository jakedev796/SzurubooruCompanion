# syntax=docker/dockerfile:1
# Use BuildKit for cache mounts

# Build stage
# Optional: pass VITE_API_BASE (e.g. https://api.ccc.example.com) if API is on a different host
FROM node:20-alpine AS build
ARG VITE_API_BASE
ENV VITE_API_BASE=${VITE_API_BASE}
WORKDIR /app
COPY package.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm install
COPY . .
RUN npm run build

# Serve stage – lightweight static file server (no nginx)
FROM node:20-alpine
RUN npm install -g serve
COPY --from=build /app/dist /app/dist
EXPOSE 21430
CMD ["serve", "-s", "/app/dist", "-l", "21430"]
