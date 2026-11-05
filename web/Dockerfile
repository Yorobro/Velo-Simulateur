# Interface web : PHP 8.3 + Apache, racine du site sur public/.

# 1. Dépendances Composer (l'image composer contient zip, unzip et git).
FROM composer:2 AS dependances
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --no-scripts --no-autoloader \
        --ignore-platform-req=ext-pdo_mysql
COPY src ./src
RUN composer dump-autoload --no-dev --optimize

# 2. Serveur
FROM php:8.3-apache

RUN docker-php-ext-install pdo_mysql \
    && a2enmod rewrite \
    && sed -ri 's#/var/www/html#/var/www/html/public#g' /etc/apache2/sites-available/000-default.conf \
    && printf 'ServerName localhost\n<Directory /var/www/html/public>\n    AllowOverride All\n</Directory>\n' \
        > /etc/apache2/conf-available/velo.conf \
    && a2enconf velo \
    && printf 'date.timezone = Europe/Paris\n' > "$PHP_INI_DIR/conf.d/velo.ini"

WORKDIR /var/www/html
COPY . .
COPY --from=dependances /app/vendor ./vendor
RUN mkdir -p var/cache && chown -R www-data:www-data var

# Connexion à la base : DB_PASSWORD est à fournir à l'exécution (docker-compose, docker run -e).
ENV DB_HOST=db \
    DB_PORT=3306 \
    DB_NAME=velo_libre_service \
    DB_USER=root \
    APP_DEBUG=0
