#!/usr/bin/env bash
# Mede o tempo de resposta (curl time_total) de um endpoint: N requests sequenciais
# após um aquecimento. Uso: scripts/medir.sh /api/pedidos [N]
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
path=${1:?uso: $0 /api/pedidos [N]}
n=${2:-50}
url="http://localhost:${APP_PORT:-8080}$path"

for _ in 1 2 3 4 5; do curl -s -o /dev/null "$url"; done

for _ in $(seq 1 "$n"); do
  curl -s -o /dev/null -w '%{time_total}\n' "$url"
done | sort -n | awk -v path="$path" '
  { t[NR] = $1 * 1000; s += $1 * 1000 }
  END {
    p95 = t[int(NR * 0.95 + 0.5)]
    printf "%-26s n=%d  mediana=%.1fms  média=%.1fms  p95=%.1fms  min=%.1fms  max=%.1fms\n",
      path, NR, t[int((NR + 1) / 2)], s / NR, p95, t[1], t[NR]
  }'
