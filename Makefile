# Demo: observabilidade em PHP com OpenTelemetry (Laravel + Collector + Tempo + Grafana)
-include .env

APP_PORT     ?= 8080
GRAFANA_PORT ?= 3000
APP_URL      := http://localhost:$(APP_PORT)
REQUESTS     ?= 20

.PHONY: help up up-log down clean load load-fast load-pagamentos trafego logs logs-collector checklist ps

help: ## Lista os comandos
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | awk 'BEGIN {FS = ":.*## "} {printf "  make %-15s %s\n", $$1, $$2}'

up: ## Sobe tudo (build + migrations + seed na primeira vez)
	docker compose up -d --build --wait
	@echo ""
	@echo "App:     $(APP_URL)/api/pedidos"
	@echo "Grafana: http://localhost:$(GRAFANA_PORT)/explore"
	@echo "Dashboard: http://localhost:$(GRAFANA_PORT)/d/demo-red"

up-log: ## Sobe com o bônus de correlação log <-> trace (psr3 inject) ligado
	OTEL_PHP_DISABLED_INSTRUMENTATIONS= docker compose up -d --build --wait

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

logs: ## Segue os logs da app e do collector
	docker compose logs -f app collector

logs-collector: ## Logs do collector com cada span detalhado (debug exporter)
	COLLECTOR_DEBUG_VERBOSITY=detailed docker compose up -d collector
	docker compose logs -f collector

checklist: ## Valida o ambiente antes da palestra
	./scripts/checklist.sh

ps: ## Estado dos containers
	docker compose ps
