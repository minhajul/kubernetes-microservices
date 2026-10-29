# syntax=docker/dockerfile:1

# composer.lock pins Symfony 8, which requires PHP >= 8.4.
ARG PHP_VERSION=8.4

# ---------------------------------------------------------------------------
# base: PHP runtime with the extensions Laravel needs (shared by all stages)
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-cli-alpine AS base

# Build tools are installed and removed in the same layer; only libpng stays.
RUN set -eux; \
    apk add --no-cache libpng; \
    apk add --no-cache --virtual .build-deps $PHPIZE_DEPS libpng-dev; \
    docker-php-ext-install -j"$(nproc)" pdo_mysql exif pcntl bcmath gd; \
    docker-php-ext-enable opcache; \
    apk del --no-network .build-deps; \
    mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

WORKDIR /var/www

# ---------------------------------------------------------------------------
# vendor: production Composer dependencies and optimized autoloader
# ---------------------------------------------------------------------------
FROM base AS vendor

RUN apk add --no-cache unzip
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_CACHE_DIR=/tmp/composer-cache

# Install dependencies from the lock file first so this layer is cached
# until composer.json / composer.lock change.
COPY composer.json composer.lock ./
RUN --mount=type=cache,target=/tmp/composer-cache \
    composer install --no-dev --no-interaction --no-progress --prefer-dist \
        --no-scripts --no-autoloader

COPY . .
# Runs post-autoload-dump, which writes bootstrap/cache/packages.php and
# services.php for the production package set.
RUN composer dump-autoload --no-dev --optimize --no-interaction

# ---------------------------------------------------------------------------
# runtime: application code + vendor, running as UID 1000
# ---------------------------------------------------------------------------
FROM base AS runtime

RUN addgroup -g 1000 app \
    && adduser -D -H -u 1000 -G app -h /var/www -s /sbin/nologin app

# Code stays owned by root (read-only for the app user); only the paths
# Laravel writes to at runtime are owned by UID 1000.
COPY --from=vendor /var/www /var/www
RUN mkdir -p \
        storage/app/public \
        storage/app/private \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs \
        bootstrap/cache \
    && chown -R 1000:1000 storage bootstrap/cache

USER 1000:1000

EXPOSE 8000

# The same image also runs `php artisan migrate --force` as an init container.
# --no-reload passes the container environment straight through to the PHP
# server and allows PHP_CLI_SERVER_WORKERS to set the worker count.
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8000", "--no-reload"]
