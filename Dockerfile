# Deterministic production image for Railway: real PHP 8.4 + real Node 22.
# Used when Settings -> Build -> Builder = "Dockerfile" (Railway builds from
# the git repo, so gitignored junk like .env / public/hot never ships).

# ---------- Stage 1: frontend build (Vite + React) ----------
FROM node:22-alpine AS frontend
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---------- Stage 2: production runtime ----------
FROM php:8.4-cli-alpine
WORKDIR /app

# pdo_mysql (DB-backed sessions/cache/analytics) + bcmath; mbstring, openssl,
# xml, tokenizer, ctype and curl are already compiled into the official image.
RUN docker-php-ext-install pdo_mysql bcmath

# unzip so composer can unpack dist archives (dev-VCS deps), git as fallback
RUN apk add --no-cache unzip git
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Dependencies first so later code changes reuse the cached layer
COPY composer.json composer.lock ./
RUN composer install --optimize-autoloader --no-scripts --no-interaction --no-progress

COPY . .
COPY --from=frontend /app/public/build ./public/build
RUN php artisan package:discover --ansi

# artisan serve is single-threaded by default; workers keep analytics
# beacons, page requests and the 62 MB showcase video from queueing.
ENV PHP_CLI_SERVER_WORKERS=4

# Migrate (sessions/cache/analytics tables) then serve; exec lets Railway's
# SIGTERM reach PHP directly on redeploy.
CMD ["sh", "-c", "php artisan migrate --force && exec php artisan serve --host=0.0.0.0 --port=${PORT:-8080}"]
