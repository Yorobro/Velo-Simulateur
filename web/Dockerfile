# Interface web : PHP 8.3 + Apache, racine du site sur public/.
FROM php:8.3-apache

RUN docker-php-ext-install pdo_mysql \
    && a2enmod rewrite \
    && sed -ri 's#/var/www/html#/var/www/html/public#g' /etc/apache2/sites-available/000-default.conf \
    && printf '<Directory /var/www/html/public>\n    AllowOverride All\n</Directory>\n' \
        > /etc/apache2/conf-available/velo.conf \
    && a2enconf velo

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Dépendances d'abord : la couche reste en cache tant que composer.* ne change pas.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --no-scripts --no-autoloader

COPY . .
RUN composer dump-autoload --optimize --no-dev \
    && mkdir -p var/cache \
    && chown -R www-data:www-data var

# Connexion à la base : à fournir à l'exécution (docker-compose, docker run -e).
ENV DB_HOST=db \
    DB_PORT=3306 \
    DB_NAME=velo_libre_service \
    DB_USER=root \
    APP_DEBUG=0
