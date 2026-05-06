FROM php:8.4-fpm

RUN apt-get update && apt-get install -y libpq-dev unzip git \                                                                                                                        
    && docker-php-ext-install pdo pdo_pgsql 

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer 

WORKDIR /app

EXPOSE 8000

CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8000"] 