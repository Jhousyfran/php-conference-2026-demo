#!/usr/bin/env bash
# Deploy da demo na VM da palestra (EC2 do deploypro), em https://demo.deploypro.com.br.
#
# Uso:
#   scripts/deploy-vm.sh            envia, pede confirmação e sobe
#   scripts/deploy-vm.sh -y         sobe sem perguntar
#   scripts/deploy-vm.sh --status   containers, memória, disco e últimas linhas do cron
#   scripts/deploy-vm.sh --parar    para a demo e remove o cron (mantém os dados)
#   scripts/deploy-vm.sh --cron-off desliga só o cron de tráfego (a demo continua no ar)
#   scripts/deploy-vm.sh --cron-on  liga o cron de novo
#   scripts/deploy-vm.sh --datadog-on  copia o .env.datadog local para a VM e passa a
#                                      mandar traces e logs também para o Datadog
#   scripts/deploy-vm.sh --datadog-off para de mandar para o Datadog
#
# A chave tem senha: carregue-a uma vez no agente antes →  ssh-add ~/.ssh/my-ssh/id_rsa
set -euo pipefail

HOST="${DEPLOY_HOST:-ubuntu@18.230.39.161}"
KEY="${DEPLOY_KEY:-$HOME/.ssh/my-ssh/id_rsa}"
REMOTE_DIR="${DEPLOY_DIR:-/data/demo-otel-php}"
DOMAIN="${DEMO_DOMAIN:-demo.deploypro.com.br}"
# Com .env.datadog na VM, o override do Datadog entra junto (avaliado lá, na hora)
COMPOSE="sudo docker compose -f docker-compose.yml -f docker-compose.vm.yml \$([ -f .env.datadog ] && echo -f docker-compose.datadog.yml) --env-file .env.vm"

cd "$(dirname "$0")/.."
SSH=(ssh -i "$KEY" -o ConnectTimeout=10)
EXCLUDES=(--exclude .git --exclude .idea --exclude .vscode
          --exclude app/vendor --exclude app/node_modules --exclude app/.env
          --exclude 'app/storage/logs/*.log' --exclude .env.vm --exclude .env.datadog
          --exclude trafego-cron.log)

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }
remote() { "${SSH[@]}" "$HOST" "$@"; }

check_connection() {
  remote true 2>/dev/null || die "não conectou em $HOST. A chave está carregada? Rode: ssh-add $KEY"
}

status() {
  check_connection
  remote "cd '$REMOTE_DIR' && $COMPOSE ps --format '{{.Name}}  {{.Status}}' \
    && echo && sudo docker stats --no-stream --format '{{.Name}}  {{.MemUsage}}  {{.CPUPerc}}' | grep demo-otel \
    && echo && free -m && df -h / /data && echo && tail -n 5 trafego-cron.log 2>/dev/null"
}

parar() {
  check_connection
  log "Removendo o cron e parando a demo (volumes mantidos)"
  remote "sudo rm -f /etc/cron.d/demo-otel-php && cd '$REMOTE_DIR' && $COMPOSE down"
}

cron_on() {
  check_connection
  log "Ligando o cron de tráfego (/etc/cron.d/demo-otel-php)"
  remote "sudo install -m 644 -o root -g root '$REMOTE_DIR/deploy/cron-demo' /etc/cron.d/demo-otel-php"
}

cron_off() {
  check_connection
  log "Desligando o cron de tráfego (a demo continua no ar)"
  remote "sudo rm -f /etc/cron.d/demo-otel-php"
}

datadog_on() {
  check_connection
  [[ -f .env.datadog ]] || die "crie o .env.datadog local (cp .env.datadog.example .env.datadog)"
  grep -qE '^DD_API_KEY=.+' .env.datadog || die "DD_API_KEY vazio em .env.datadog"
  log "Enviando .env.datadog para a VM (chmod 600) e recriando o Collector"
  "${SSH[@]}" "$HOST" "umask 077 && cat > '$REMOTE_DIR/.env.datadog'" < .env.datadog
  remote "cd '$REMOTE_DIR' && $COMPOSE up -d --wait collector"
}

datadog_off() {
  check_connection
  log "Removendo .env.datadog da VM e recriando o Collector sem o Datadog"
  remote "rm -f '$REMOTE_DIR/.env.datadog' && cd '$REMOTE_DIR' && $COMPOSE up -d --wait collector"
}

YES=0
case "${1:-}" in
  --status)   status; exit 0 ;;
  --parar)    parar; exit 0 ;;
  --cron-on)  cron_on; exit 0 ;;
  --cron-off) cron_off; exit 0 ;;
  --datadog-on)  datadog_on; exit 0 ;;
  --datadog-off) datadog_off; exit 0 ;;
  -y|--yes)   YES=1 ;;
  "")         ;;
  *)          sed -n '2,15p' "$0"; exit 1 ;;
esac

[[ -f docker-compose.vm.yml ]] || die "rode a partir do repositório da demo."
if [[ -n "$(git status --porcelain)" ]]; then
  log "Aviso: há alterações não commitadas. Elas serão publicadas mesmo assim."
fi

check_connection

log "Recursos da VM antes do deploy"
remote "free -m | awk 'NR==2 {print \"  memória disponível: \" \$7 \" MB\"}'; df -h / /data | awk 'NR>1 {print \"  disco \" \$6 \": \" \$5 \" usado, \" \$4 \" livre\"}'"

if [[ $YES -eq 0 ]]; then
  read -r -p "Enviar e subir a demo em $HOST:$REMOTE_DIR? [s/N] " ans
  [[ "$ans" =~ ^[sS]$ ]] || { log "Cancelado."; exit 0; }
fi

# 1) código
log "Enviando o código para $REMOTE_DIR"
remote "sudo mkdir -p '$REMOTE_DIR' && sudo chown \$(id -u):\$(id -g) '$REMOTE_DIR'"
rsync -az --delete "${EXCLUDES[@]}" -e "${SSH[*]}" ./ "$HOST:$REMOTE_DIR/"

# 2) .env.vm (só na primeira vez: senha aleatória do admin do Grafana)
remote "cd '$REMOTE_DIR' && if [ ! -f .env.vm ]; then
  sed \"s/^GRAFANA_ADMIN_PASSWORD=.*/GRAFANA_ADMIN_PASSWORD=\$(openssl rand -hex 12)/\" .env.vm.example > .env.vm
  chmod 600 .env.vm; echo '  .env.vm criado (senha do admin: grep GRAFANA_ADMIN_PASSWORD $REMOTE_DIR/.env.vm)'
fi"

# 3) containers (build da imagem PHP na própria VM: arm64)
log "Subindo os containers (build na VM; a primeira vez leva alguns minutos)"
remote "cd '$REMOTE_DIR' && $COMPOSE up -d --build --wait --remove-orphans"
# imagens antigas fora; cache de build limitado a 1 GB (mantém o próximo build rápido)
remote "sudo docker image prune -f >/dev/null && sudo docker builder prune -af --max-used-space 1GB >/dev/null"

# 4) nginx do host: certificado primeiro (certonly não edita a config do nginx), depois
# a config do repositório. Se o nginx -t falhar, volta a anterior: os outros sites da VM
# nunca ficam com uma config quebrada.
if ! remote "sudo test -d /etc/letsencrypt/live/$DOMAIN"; then
  log "Emitindo o certificado HTTPS (certbot certonly)"
  remote "sudo certbot certonly --nginx -d '$DOMAIN' --non-interactive --agree-tos"
fi
log "Configurando o nginx para $DOMAIN"
remote "conf=/etc/nginx/sites-available/demo-otel-php
  sudo test -f \$conf && sudo cp \$conf \$conf.anterior
  sudo cp '$REMOTE_DIR/deploy/nginx-demo.conf' \$conf
  sudo ln -sf \$conf /etc/nginx/sites-enabled/demo-otel-php
  if sudo nginx -t 2>/tmp/nginx-t.log; then
    sudo systemctl reload nginx
  else
    cat /tmp/nginx-t.log
    if sudo test -f \$conf.anterior; then sudo mv \$conf.anterior \$conf; else sudo rm -f \$conf /etc/nginx/sites-enabled/demo-otel-php; fi
    echo 'nginx -t falhou: config anterior restaurada'; exit 1
  fi"

# 5) cron: o deploy não liga nem desliga (make vm-cron-on / vm-cron-off)
if remote "test -f /etc/cron.d/demo-otel-php"; then log "Cron de tráfego: ligado"
else log "Cron de tráfego: desligado (para ligar: make vm-cron-on)"; fi

# 6) smoke test
log "Conferindo"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$DOMAIN/api/health")
[[ "$code" == "200" ]] || die "Grafana não respondeu 200 em https://$DOMAIN/api/health (veio $code)"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$DOMAIN/api/dashboards/uid/demo-red")
[[ "$code" == "200" ]] || die "dashboard demo-red não abriu para anônimo (veio $code)"
remote "curl -s -o /dev/null -w '  app (127.0.0.1:8090): %{http_code}\n' http://127.0.0.1:8090/api/pedidos-otimizado"
log "No ar: https://$DOMAIN/d/demo-red"
