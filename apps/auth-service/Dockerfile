FROM php:8.3-cli

# Install system dependencies and PHP extensions needed for Laravel
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    zip \
    unzip \
    git \
    curl \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd

# Get Composer (PHP Package Manager)
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www

# Copy the Laravel project files
COPY . .

# Install PHP dependencies
# Note: In production, you would run --no-dev --optimize-autoloader
RUN composer install

# Expose port 8000
EXPOSE 8000

# Start Laravel using the built-in server
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8000"]
