# Deterministic production image for Railway: real PHP 8.4 runtime, Vite-built
# assets. Built with the "Dockerfile" builder (Railway builds from the git
# repo, so gitignored junk like .env / public/hot never ships).
#
# Single build stage with PHP AND Node together: `npm run build` shells out to
# `php artisan wayfinder:generate --with-form` (@laravel/vite-plugin-wayfinder),
# which needs artisan + vendor/ + the full Laravel source — a bare node stage
# cannot do that. One combined stage also serializes the npm and compiler
# work, keeping peak memory low on Railway's memory-capped builder.

# ---------- Stage 1: build (PHP + Node together) ----------
FROM php:8.4-cli-alpine AS build
WORKDIR /app

# pdo_mysql for the runtime image (DB-backed sessions/cache/analytics).
# bcmath is intentionally not compiled: composer.json does not require it
# (it only appears in "suggest" sections of composer.lock).
# -j1 keeps the compile strictly serial (default, made explicit) — this exact
# step died repeatedly before, most plausibly memory contention with the
# frontend stage that used to build in parallel.
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && docker-php-ext-install -j1 pdo_mysql \
    && apk del .build-deps

# Node (engines only require >=22.13) + the tools composer needs for
# extracting dist archives
RUN apk add --no-cache nodejs npm unzip git
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# PHP dependencies first so later code changes reuse the cached layer
COPY composer.json composer.lock ./
RUN composer install --optimize-autoloader --no-scripts --no-interaction --no-progress

# JS dependencies
COPY package.json package-lock.json ./
RUN npm ci

# Full source, then build assets — the wayfinder Vite plugin runs
# `php artisan wayfinder:generate` here, so php + vendor must already exist.
COPY . .
RUN npm run build

# ---------- Stage 2: production runtime (no Node, no build tools) ----------
FROM php:8.4-cli-alpine
WORKDIR /app

# Same base image as the build stage, so the compiled extension transfers
# directly — no second compile, no build tools in the runtime image.
COPY --from=build /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=build /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/

COPY --from=build /app/vendor ./vendor
COPY --from=build /app/app ./app
COPY --from=build /app/bootstrap ./bootstrap
COPY --from=build /app/config ./config
COPY --from=build /app/database ./database
COPY --from=build /app/public ./public
COPY --from=build /app/resources ./resources
COPY --from=build /app/routes ./routes
COPY --from=build /app/storage ./storage
COPY --from=build /app/artisan ./artisan
COPY --from=build /app/composer.json /app/composer.lock ./

RUN php artisan package:discover --ansi

# artisan serve is single-threaded by default; workers keep analytics
# beacons, page requests and the 62 MB showcase video from queueing.
ENV PHP_CLI_SERVER_WORKERS=4

# Migrate (sessions/cache/analytics tables) then serve; exec lets Railway's
# SIGTERM reach PHP directly on redeploy.
CMD ["sh", "-c", "php artisan migrate --force && exec php artisan serve --host=0.0.0.0 --port=${PORT:-8080}"]
