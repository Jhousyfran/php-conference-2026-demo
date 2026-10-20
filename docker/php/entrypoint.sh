#!/bin/sh
# Entrypoint idempotente: espera o MySQL, roda migrations e seed (o seeder
# só popula se a tabela de clientes estiver vazia) e inicia o PHP-FPM.
set -e

cd /var/www/html

# Os comandos de bootstrap não devem gerar traces (seriam centenas de spans de INSERT).
export_off() { OTEL_SDK_DISABLED=true OTEL_PHP_AUTOLOAD_ENABLED=false "$@"; }

# O app/.env não vai para o git nem para a imagem: gera a partir do .env.example.
if [ ! -f .env ]; then
  cp .env.example .env
  export_off php artisan key:generate --force --no-interaction
fi

echo "[entrypoint] aguardando o banco..."
i=0
until export_off php artisan migrate --force --no-interaction; do
  i=$((i + 1))
  if [ "$i" -ge 30 ]; then
    echo "[entrypoint] banco não respondeu após 30 tentativas" >&2
    exit 1
  fi
  sleep 2
done

export_off php artisan db:seed --force --no-interaction

# Cache de config/rotas: deixa a request mais enxuta durante a demo
export_off php artisan config:cache
export_off php artisan route:cache

chown -R www-data:www-data storage bootstrap/cache

exec "$@"
