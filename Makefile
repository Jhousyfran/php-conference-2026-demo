# Demo: observabilidade em PHP com OpenTelemetry (Laravel + Collector + Tempo + Grafana)
-include .env

APP_PORT     ?= 8080
GRAFANA_PORT ?= 3000
APP_URL      := http://localhost:$(APP_PORT)
REQUESTS     ?= 20

.PHONY: help up deploy up-datadog down clean load load-fast load-pagamentos trafego log-app logs logs-collector checklist ps

help: ## Lista os comandos
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | awk 'BEGIN {FS = ":.*## "} {printf "  make %-15s %s\n", $$1, $$2}'

up: ## Sobe tudo (build + migrations + seed na primeira vez)
	docker compose up -d --build --wait
	@echo ""
	@echo "App:     $(APP_URL)/api/pedidos"
	@echo "Grafana: http://localhost:$(GRAFANA_PORT)/explore"
	@echo "Dashboard: http://localhost:$(GRAFANA_PORT)/d/demo-red"

deploy: ## Simula um deploy: make deploy VERSAO=1.1.0 TAXA_ERRO=50 (só recria a app)
	APP_VERSION=$(or $(VERSAO),1.1.0) PAGAMENTO_TAXA_ERRO=$(or $(TAXA_ERRO),20) docker compose up -d --wait app
	@echo "app na versão $(or $(VERSAO),1.1.0), taxa de erro do gateway $(or $(TAXA_ERRO),20)%"

up-datadog: ## Sobe tudo mandando traces e logs TAMBÉM para o Datadog (precisa de .env.datadog)
	@test -f .env.datadog || { echo "Crie o .env.datadog: cp .env.datadog.example .env.datadog e preencha DD_API_KEY"; exit 1; }
	@grep -qE '^DD_API_KEY=.+' .env.datadog || { echo "DD_API_KEY vazio em .env.datadog"; exit 1; }
	docker compose -f docker-compose.yml -f docker-compose.datadog.yml up -d --build --wait
	@echo "Datadog: APM -> Services -> demo-pedidos (env:demo)"

down: ## Para os containers (mantém banco e traces)
	docker compose down

clean: ## Para e apaga volumes (banco e traces)
	docker compose down -v

load: ## ~20 requests no endpoint com N+1
	@for i in $$(seq 1 $(REQUESTS)); do \
		curl -s -o /dev/null -w "GET /api/pedidos            %{http_code}  %{time_total}s\n" $(APP_URL)/api/pedidos; \
	done

load-fast: ## ~20 requests no endpoint otimizado (eager loading)
	@for i in $$(seq 1 $(REQUESTS)); do \
		curl -s -o /dev/null -w "GET /api/pedidos-otimizado  %{http_code}  %{time_total}s\n" $(APP_URL)/api/pedidos-otimizado; \
	done

load-pagamentos: ## ~20 POSTs no endpoint de pagamento (~20% falham com HTTP 500)
	@for i in $$(seq 1 $(REQUESTS)); do \
		curl -s -o /dev/null -w "POST /api/pagamentos         %{http_code}  %{time_total}s\n" -X POST $(APP_URL)/api/pagamentos; \
	done

trafego: ## Tráfego misto por DURACAO segundos (padrão 120) para o dashboard RED
	./scripts/trafego.sh $(or $(DURACAO),120)

log-app: ## Últimas linhas do laravel.log (com trace_id/span_id)
	docker compose exec app tail -n 20 storage/logs/laravel.log

logs: ## Segue os logs da app e do collector
	docker compose logs -f app collector

logs-collector: ## Logs do collector com cada span detalhado (debug exporter)
	COLLECTOR_DEBUG_VERBOSITY=detailed docker compose up -d collector
	docker compose logs -f collector

checklist: ## Valida o ambiente antes da palestra
	./scripts/checklist.sh

ps: ## Estado dos containers
	docker compose ps
