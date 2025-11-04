# Stage 1: Build PHP dependencies
FROM composer:2.7 as vendor
WORKDIR /app

# Copy composer files
COPY composer.json composer.lock ./

# Install dependencies
RUN composer install \
    --no-dev \
    --no-interaction \
    --optimize-autoloader \
    --ignore-platform-reqs \
    --no-scripts \
    --prefer-dist

# -----------------------------------------------

# Stage 2: Build frontend assets
FROM node:22-alpine as assets
WORKDIR /app

# Copy package files
COPY package.json package-lock.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source files needed for build
COPY . .

# Build assets
RUN npm run build

# -----------------------------------------------

# Stage 3: The final production image
FROM php:8.2-fpm-alpine

# Set working directory
WORKDIR /var/www/html

# Clean up build dependencies
RUN rm -rf /tmp/* /var/cache/apk/*

# Copy built dependencies from other stages
COPY --from=vendor --chown=www-data:www-data /app/vendor/ /var/www/html/vendor/
COPY --from=assets --chown=www-data:www-data /app/public/build/ /var/www/html/public/build/

# Copy application files
COPY --chown=www-data:www-data . .

# Create necessary directories and set permissions
RUN mkdir -p \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs \
        bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Optimize Laravel (cache config, routes, views)
#RUN php artisan config:cache \
#    && php artisan route:cache \
#    && php artisan view:cache

# Switch to www-data user
USER www-data

# Expose port 9000 for PHP-FPM
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD php-fpm -t || exit 1

CMD ["php-fpm"]
