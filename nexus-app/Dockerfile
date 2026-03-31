# ============================================================
# WATCHTOWER SOC PLATFORM v3.0
# Archivo: nexus-app/Dockerfile
# Descripción: Imagen Docker para la app Nexus Fintech
# ============================================================

# ── CAPA BASE ──────────────────────────────────
# python:3.11-slim = Python 3.11 sobre Debian minimal
# "slim" = imagen más pequeña, menos vulnerabilidades
FROM python:3.11-slim

# Metadatos de la imagen (buena práctica)
LABEL maintainer="Watchtower SOC Team"
LABEL description="Nexus Fintech API - SOC Training Target"
LABEL version="3.0"

# ── VARIABLES DE ENTORNO ───────────────────────
# PYTHONDONTWRITEBYTECODE: No crea archivos .pyc (más limpio)
# PYTHONUNBUFFERED: Los logs aparecen en tiempo real en Docker
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    FLASK_ENV=production

# ── DIRECTORIO DE TRABAJO ──────────────────────
# Todas las operaciones siguientes ocurren aquí
# dentro del contenedor
WORKDIR /app

# ── INSTALAR DEPENDENCIAS DEL SISTEMA ──────────
# libpq-dev: necesario para psycopg2 (conector PostgreSQL)
# gcc: compilador necesario durante la instalación
# Luego los eliminamos para reducir el tamaño de la imagen
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libpq-dev \
        gcc \
    && rm -rf /var/lib/apt/lists/*

# ── INSTALAR DEPENDENCIAS PYTHON ───────────────
# Primero copiamos solo requirements.txt
# (si no cambia, Docker usa caché y es más rápido)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── COPIAR CÓDIGO FUENTE ───────────────────────
# Copiamos el resto de archivos DESPUÉS de las deps
# (optimización de capas Docker)
COPY app.py .

# ── USUARIO NO-ROOT ────────────────────────────
# Seguridad: la app no corre como root dentro del contenedor
# Si hay un exploit, el atacante no tiene privilegios de root
RUN useradd --no-create-home --shell /bin/false nexus
USER nexus

# ── PUERTO EXPUESTO ────────────────────────────
# Documentación de qué puerto usa la app
EXPOSE 8080

# ── COMANDO DE INICIO ──────────────────────────
# Gunicorn: servidor web de producción
# -w 2: 2 workers (procesos) para manejar requests
# -b 0.0.0.0:8080: escucha en todos los interfaces
# --access-logfile -: logs de acceso a stdout (Docker los captura)
CMD ["gunicorn", \
     "--workers", "2", \
     "--bind", "0.0.0.0:8080", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "--log-level", "info", \
     "app:app"]
