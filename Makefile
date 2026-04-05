# ============================================================
# WATCHTOWER SOC PLATFORM v3.0
# Archivo: Makefile
# Descripción: Comandos simplificados para operar la plataforma
# Uso: make <comando>
# ============================================================

# Variables globales
# Estas variables se usan en todos los comandos de abajo
COMPOSE_FILE := docker/docker-compose.yml
COMPOSE_CMD  := docker compose -f $(COMPOSE_FILE)
PROJECT_NAME := watchtower

# Color para mensajes en terminal
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m  # No Color (resetea el color)

# .PHONY le dice a Make que estos no son archivos reales
# sino nombres de comandos (targets)
.PHONY: help deploy stop restart status logs clean \
        harden check-health attack-sim report save

# ──────────────────────────────────────────────
# help — Muestra todos los comandos disponibles
# Este es el comando por defecto si escribes solo "make"
# ──────────────────────────────────────────────
help:
	@echo ""
	@echo "$(GREEN)╔══════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║     WATCHTOWER SOC PLATFORM v3.0             ║$(NC)"
	@echo "$(GREEN)║     Comandos disponibles                     ║$(NC)"
	@echo "$(GREEN)╚══════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)DESPLIEGUE:$(NC)"
	@echo "  make deploy          → Levanta toda la plataforma"
	@echo "  make stop            → Detiene todos los contenedores"
	@echo "  make restart         → Reinicia todos los contenedores"
	@echo "  make clean           → Elimina contenedores y volúmenes"
	@echo ""
	@echo "$(YELLOW)MONITOREO:$(NC)"
	@echo "  make status          → Estado de todos los contenedores"
	@echo "  make check-health    → Verificación de salud completa"
	@echo "  make logs            → Logs de todos los servicios"
	@echo "  make logs-wazuh      → Logs solo del Wazuh Manager"
	@echo "  make logs-app        → Logs solo de la app Nexus"
	@echo ""
	@echo "$(YELLOW)SEGURIDAD:$(NC)"
	@echo "  make harden          → Aplica hardening post-despliegue"
	@echo "  make attack-sim      → Ejecuta simulación de ataques"
	@echo "  make report          → Genera reporte de seguridad"
	@echo ""
	@echo "$(YELLOW)GIT:$(NC)"
	@echo "  make save msg='...'  → Guarda cambios en GitHub"
	@echo ""

# ──────────────────────────────────────────────
# deploy — Levanta toda la plataforma
# Qué hace paso a paso:
# 1. Verifica que Docker está corriendo
# 2. Construye las imágenes personalizadas (nexus-app)
# 3. Levanta todos los contenedores en segundo plano (-d)
# 4. Muestra el estado final
# ──────────────────────────────────────────────
deploy:
	@echo "$(GREEN)🚀 Iniciando Watchtower SOC Platform...$(NC)"
	@echo "$(YELLOW)⏳ Esto puede tomar 3-5 minutos la primera vez$(NC)"
	@echo "   (Docker descarga las imágenes de Wazuh ~2GB)"
	@echo ""
	$(COMPOSE_CMD) up -d --build
	@echo ""
	@echo "$(GREEN)✅ Plataforma iniciada. Verificando estado...$(NC)"
	@sleep 5
	@$(MAKE) status

# ──────────────────────────────────────────────
# stop — Detiene todos los contenedores
# Los datos se CONSERVAN (volúmenes Docker intactos)
# ──────────────────────────────────────────────
stop:
	@echo "$(YELLOW)⏹️  Deteniendo Watchtower SOC Platform...$(NC)"
	$(COMPOSE_CMD) stop
	@echo "$(GREEN)✅ Plataforma detenida. Los datos están seguros.$(NC)"

# ──────────────────────────────────────────────
# restart — Reinicia todos los contenedores
# Útil cuando cambias una configuración y necesitas
# que el servicio la aplique sin perder datos
# ──────────────────────────────────────────────
restart:
	@echo "$(YELLOW)🔄 Reiniciando Watchtower SOC Platform...$(NC)"
	$(COMPOSE_CMD) restart
	@sleep 5
	@$(MAKE) status

# ──────────────────────────────────────────────
# status — Muestra el estado de todos los contenedores
# Formato tabla: nombre, estado, puertos abiertos
# ──────────────────────────────────────────────
status:
	@echo ""
	@echo "$(GREEN)📊 Estado de la Plataforma SOC:$(NC)"
	@echo "────────────────────────────────────────────────"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
		--filter "network=soc_network" 2>/dev/null || \
		echo "$(RED)⚠️  No hay contenedores corriendo$(NC)"
	@echo ""

# ──────────────────────────────────────────────
# check-health — Verificación de salud completa
# Prueba que cada servicio responde correctamente
# ──────────────────────────────────────────────
check-health:
	@echo "$(GREEN)🏥 Verificando salud de los servicios...$(NC)"
	@echo ""
	@echo "1. Wazuh Indexer (OpenSearch):"
	@docker exec wazuh.indexer curl -sk \
		-u admin:SecurePassword123! \
		"https://localhost:9200/_cluster/health?pretty" \
		2>/dev/null | grep -E '"status"|"number_of_nodes"' || \
		echo "   $(RED)❌ No responde$(NC)"
	@echo ""
	@echo "2. Wazuh Manager API:"
	@docker exec wazuh.manager \
		curl -sk -u wazuh-wui:MyS3cr37P450r.*- \
		"https://localhost:55000/" \
		2>/dev/null | grep -E '"title"|"api_version"' || \
		echo "   $(RED)❌ No responde$(NC)"
	@echo ""
	@echo "3. Nexus Fintech App:"
	@curl -s "http://localhost:8080/health" \
		2>/dev/null || echo "   $(RED)❌ No responde$(NC)"
	@echo ""
	@echo "4. Grafana:"
	@curl -s "http://localhost:3000/api/health" \
		2>/dev/null | grep -o '"database":"ok"' || \
		echo "   $(RED)❌ No responde$(NC)"
	@echo ""

# ──────────────────────────────────────────────
# logs — Muestra logs en tiempo real de TODO
# Ctrl+C para salir
# ──────────────────────────────────────────────
logs:
	@echo "$(YELLOW)📋 Mostrando logs (Ctrl+C para salir)...$(NC)"
	$(COMPOSE_CMD) logs -f --tail=50

# logs-wazuh — Solo logs del Manager
logs-wazuh:
	@echo "$(YELLOW)📋 Logs de Wazuh Manager (Ctrl+C para salir)...$(NC)"
	$(COMPOSE_CMD) logs -f --tail=50 wazuh.manager

# logs-app — Solo logs de la app Nexus
logs-app:
	@echo "$(YELLOW)📋 Logs de Nexus App (Ctrl+C para salir)...$(NC)"
	$(COMPOSE_CMD) logs -f --tail=50 nexus-app

# ──────────────────────────────────────────────
# harden — Aplica hardening post-despliegue
# Ejecuta los pasos de seguridad adicionales
# después de que los contenedores están corriendo
# ──────────────────────────────────────────────
harden:
	@echo "$(GREEN)🔒 Aplicando hardening de seguridad...$(NC)"
	@echo ""
	@echo "1. Verificando certificados TLS..."
	@docker exec wazuh.indexer \
		ls -la /usr/share/wazuh-indexer/certs/ 2>/dev/null || \
		echo "   $(YELLOW)⚠️  Revisar certificados$(NC)"
	@echo ""
	@echo "2. Verificando servicios Wazuh internos..."
	@docker exec wazuh.manager \
		/var/ossec/bin/wazuh-control status 2>/dev/null || \
		echo "   $(YELLOW)⚠️  Revisar servicios$(NC)"
	@echo ""
	@echo "$(GREEN)✅ Hardening verificado$(NC)"

# ──────────────────────────────────────────────
# attack-sim — Ejecuta simulación de ataques
# Lanza los scripts de Red Team de forma controlada
# SOLO para uso en este entorno de laboratorio
# ──────────────────────────────────────────────
attack-sim:
	@echo "$(RED)⚠️  INICIANDO SIMULACIÓN DE ATAQUE$(NC)"
	@echo "$(YELLOW)   Solo para uso en entorno de laboratorio$(NC)"
	@echo ""
	@echo "Selecciona el escenario:"
	@echo "  1. Brute Force SSH"
	@echo "  2. SQL Injection"
	@echo "  3. Data Exfiltration"
	@echo ""
	@echo "Ejecuta: python3 attack-simulations/<script>.py"

# ──────────────────────────────────────────────
# clean — ELIMINA todo (contenedores + volúmenes)
# ⚠️  ADVERTENCIA: Borra todos los datos del SIEM
# Úsalo solo si quieres empezar desde cero
# ──────────────────────────────────────────────
clean:
	@echo "$(RED)⚠️  ADVERTENCIA: Esto eliminará TODOS los datos$(NC)"
	@echo "   Alertas, logs, configuraciones del SIEM"
	@echo "   Presiona Ctrl+C en los próximos 5 segundos para cancelar"
	@sleep 5
	$(COMPOSE_CMD) down -v --remove-orphans
	@echo "$(GREEN)✅ Limpieza completada. Puedes hacer make deploy$(NC)"

# ──────────────────────────────────────────────
# save — Guarda cambios en GitHub
# Uso: make save msg="descripción de los cambios"
# ──────────────────────────────────────────────
save:
	@echo "$(GREEN)💾 Guardando cambios en GitHub...$(NC)"
	git add .
	git commit -m "$(msg)" 2>/dev/null || \
		echo "$(YELLOW)ℹ️  No hay cambios nuevos para guardar$(NC)"
	git push origin main
	@echo "$(GREEN)✅ Cambios guardados en GitHub$(NC)"

# ──────────────────────────────────────────────
# report — Genera reporte básico de estado
# ──────────────────────────────────────────────
report:
	@echo "$(GREEN)📄 Generando reporte de estado...$(NC)"
	@echo "# Watchtower SOC Report - $$(date)" > reports/status-report.md
	@echo "" >> reports/status-report.md
	@echo "## Estado de Contenedores" >> reports/status-report.md
	@docker ps --format "| {{.Names}} | {{.Status}} | {{.Ports}} |" \
		--filter "network=soc_network" >> reports/status-report.md
	@echo "" >> reports/status-report.md
	@echo "$(GREEN)✅ Reporte guardado en reports/status-report.md$(NC)"
