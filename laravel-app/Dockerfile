# Stage 1: Build PHP dependencies
FROM composer:2 as vendor
WORKDIR /app
COPY database/ database/
COPY routes/ routes/
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --optimize-autoloader

# Stage 2: Build frontend assets
FROM node:18 as assets
WORKDIR /app
COPY package.json package.lock ./
RUN npm install
COPY . .
RUN npm run build

# Stage 3: The final production image
FROM php:8.2-fpm-alpine
WORKDIR /app

# Install system dependencies (e.g., for Postgres or MySQL)
# Example for Postgres:
RUN apk add --no-cache libpq-dev $PHPIZE_DEPS \
    && pecl install redis \
    && docker-php-ext-install pdo pdo_pgsql \
    && docker-php-ext-enable redis pdo pdo_pgsql

# Copy built dependencies from other stages
COPY --from=vendor /app/vendor/ /app/vendor/
COPY --from=assets /app/public/ /app/public/

# Copy the rest of the application
COPY . .

# Set correct permissions
RUN chown -R www-data:www-data /app/storage /app/bootstrap/cache \
    && chmod -R 775 /app/storage /app/bootstrap/cache

# Expose port 9000 for PHP-FPM
EXPOSE 9000
CMD ["php-fpm"]
