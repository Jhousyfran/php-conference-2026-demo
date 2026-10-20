FROM php:8.3-fpm-bookworm

# Instalador oficial de extensões (mlocati/docker-php-extension-installer)
COPY --from=mlocati/php-extension-installer:2.12.2 /usr/bin/install-php-extensions /usr/local/bin/

# - opentelemetry: extensão PECL que permite os hooks da auto-instrumentação
# - protobuf: opcional, acelera a serialização OTLP http/protobuf
# - pdo_mysql: driver do banco
RUN install-php-extensions opentelemetry-1.4.2 protobuf pdo_mysql zip @composer

# Mantém as variáveis de ambiente do container visíveis para o PHP-FPM
# (o SDK do OpenTelemetry lê OTEL_* do ambiente antes do Laravel carregar o .env)
COPY docker/php/zz-otel.conf /usr/local/etc/php-fpm.d/zz-otel.conf

WORKDIR /var/www/html

COPY app/composer.json app/composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --no-interaction --prefer-dist

COPY app/ ./
RUN composer dump-autoload --optimize --no-dev \
    && chown -R www-data:www-data storage bootstrap/cache

COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
CMD ["php-fpm"]
