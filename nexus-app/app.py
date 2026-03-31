# ============================================================
# WATCHTOWER SOC PLATFORM v3.0
# Archivo: nexus-app/app.py
# Descripción: API REST de Nexus Fintech (objetivo de ataques)
# AVISO: Vulnerabilidades intencionales para fines educativos
# ============================================================

import os
import logging
import psycopg2
import psycopg2.extras
from flask import Flask, request, jsonify
from datetime import datetime

# ──────────────────────────────────────────────
# CONFIGURACIÓN DE LOGGING
# Cada request se loguea en formato que Wazuh
# puede parsear y analizar con sus reglas
# ──────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s NEXUS-APP %(levelname)s %(message)s',
    handlers=[
        logging.StreamHandler(),           # Salida a consola (Docker logs)
        logging.FileHandler('/tmp/nexus-app.log')  # Archivo de log
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# ──────────────────────────────────────────────
# CONEXIÓN A LA BASE DE DATOS
# Lee las credenciales desde variables de entorno
# (definidas en el docker-compose.yml)
# ──────────────────────────────────────────────
def get_db_connection():
    """
    Crea y retorna una conexión a PostgreSQL.
    Si falla, loguea el error (Wazuh lo detectará).
    """
    try:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST', 'nexus-db'),
            port=os.environ.get('DB_PORT', 5432),
            dbname=os.environ.get('DB_NAME', 'nexus_fintech'),
            user=os.environ.get('DB_USER', 'nexus_user'),
            password=os.environ.get('DB_PASSWORD', 'NexusDB2024!')
        )
        return conn
    except Exception as e:
        logger.error(f"DB_CONNECTION_ERROR: {str(e)}")
        return None


# ──────────────────────────────────────────────
# HELPER: Registrar intentos de autenticación
# Guarda en DB cada intento (exitoso o fallido)
# Wazuh leerá estos logs para detectar brute force
# ──────────────────────────────────────────────
def log_auth_attempt(username, ip, success, user_agent):
    conn = get_db_connection()
    if conn:
        try:
            cur = conn.cursor()
            cur.execute(
                """INSERT INTO auth_logs
                   (username, ip_address, success, user_agent)
                   VALUES (%s, %s, %s, %s)""",
                (username, ip, success, user_agent)
            )
            conn.commit()
            cur.close()
        except Exception as e:
            logger.error(f"AUTH_LOG_ERROR: {str(e)}")
        finally:
            conn.close()


# ══════════════════════════════════════════════
# ENDPOINTS DE LA API
# ══════════════════════════════════════════════

@app.route('/health', methods=['GET'])
def health_check():
    """
    Endpoint de salud — verifica que la app y DB están OK.
    Prometheus lo llama cada 15 segundos para métricas.
    """
    conn = get_db_connection()
    if conn:
        conn.close()
        return jsonify({
            "status": "healthy",
            "service": "nexus-fintech-api",
            "timestamp": datetime.now().isoformat()
        }), 200
    return jsonify({"status": "unhealthy", "error": "DB unreachable"}), 503


@app.route('/api/login', methods=['POST'])
def login():
    """
    Endpoint de autenticación.

    ⚠️  VULNERABILIDAD INTENCIONAL: SQL Injection
    El parámetro 'username' se concatena directamente
    en la query SQL sin sanitización.

    Ataque ejemplo:
    username = "admin'--"
    Query resultante: SELECT * FROM system_users
                      WHERE username = 'admin'--' AND ...
    El '--' comenta el resto, saltándose la password.

    Wazuh detectará el patrón SQLi en los logs.
    """
    data = request.get_json()
    username = data.get('username', '')
    password = data.get('password', '')
    ip = request.remote_addr
    user_agent = request.headers.get('User-Agent', 'unknown')

    # Log de cada intento (Wazuh lo monitoreará)
    logger.info(
        f"AUTH_ATTEMPT: user={username} "
        f"ip={ip} ua={user_agent}"
    )

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Service unavailable"}), 503

    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # ⚠️ QUERY VULNERABLE — No usar en producción real
        # La f-string permite inyección SQL directa
        query = f"""
            SELECT id, username, role
            FROM system_users
            WHERE username = '{username}'
            AND password_hash = md5('{password}')
            AND is_active = true
        """
        logger.info(f"SQL_QUERY: {query.strip()}")
        cur.execute(query)
        user = cur.fetchone()

        if user:
            log_auth_attempt(username, ip, True, user_agent)
            logger.info(
                f"AUTH_SUCCESS: user={username} "
                f"role={user['role']} ip={ip}"
            )
            return jsonify({
                "status": "success",
                "user": dict(user),
                "token": f"nexus-token-{user['id']}-{datetime.now().timestamp()}"
            }), 200
        else:
            log_auth_attempt(username, ip, False, user_agent)
            logger.warning(
                f"AUTH_FAILED: user={username} ip={ip} "
                f"reason=invalid_credentials"
            )
            return jsonify({"error": "Invalid credentials"}), 401

    except Exception as e:
        logger.error(f"LOGIN_ERROR: {str(e)} user={username} ip={ip}")
        return jsonify({"error": "Internal error"}), 500
    finally:
        conn.close()


@app.route('/api/customers', methods=['GET'])
def get_customers():
    """
    Endpoint para listar clientes.

    ⚠️  VULNERABILIDAD INTENCIONAL: Exposición masiva de PII
    No tiene paginación obligatoria ni autenticación real.
    Un atacante puede extraer los 1,000 registros de una sola vez.

    Wazuh detectará el volumen anómalo de datos retornados
    mediante la regla de exfiltración que crearemos.
    """
    limit = request.args.get('limit', 100)
    offset = request.args.get('offset', 0)
    search = request.args.get('search', '')
    ip = request.remote_addr

    logger.info(
        f"CUSTOMERS_QUERY: ip={ip} "
        f"limit={limit} offset={offset} search={search}"
    )

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Service unavailable"}), 503

    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        if search:
            # ⚠️ También vulnerable a SQLi en el parámetro search
            query = f"""
                SELECT id, full_name, email, phone,
                       card_number, balance, account_status
                FROM customers
                WHERE full_name ILIKE '%{search}%'
                OR email ILIKE '%{search}%'
                LIMIT {limit} OFFSET {offset}
            """
            logger.info(f"SQL_SEARCH_QUERY: {query.strip()}")
        else:
            query = f"""
                SELECT id, full_name, email, phone,
                       card_number, balance, account_status
                FROM customers
                LIMIT {limit} OFFSET {offset}
            """

        cur.execute(query)
        customers = cur.fetchall()

        # Log del volumen de datos retornados
        # Si son >100 registros, Wazuh disparará alerta de exfiltración
        logger.warning(
            f"PII_DATA_ACCESS: ip={ip} "
            f"records_returned={len(customers)} "
            f"limit={limit}"
        )

        return jsonify({
            "status": "success",
            "count": len(customers),
            "data": [dict(c) for c in customers]
        }), 200

    except Exception as e:
        logger.error(f"CUSTOMERS_ERROR: {str(e)} ip={ip}")
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()


@app.route('/api/customers/<int:customer_id>', methods=['GET'])
def get_customer(customer_id):
    """Obtiene un cliente específico por ID."""
    ip = request.remote_addr
    logger.info(f"CUSTOMER_DETAIL: id={customer_id} ip={ip}")

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Service unavailable"}), 503

    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(
            "SELECT * FROM customers WHERE id = %s",
            (customer_id,)
        )
        customer = cur.fetchone()

        if customer:
            return jsonify({"status": "success", "data": dict(customer)}), 200
        return jsonify({"error": "Customer not found"}), 404

    except Exception as e:
        logger.error(f"CUSTOMER_DETAIL_ERROR: {str(e)}")
        return jsonify({"error": "Internal error"}), 500
    finally:
        conn.close()


@app.route('/api/transactions', methods=['GET'])
def get_transactions():
    """Lista transacciones con posible filtro por cliente."""
    customer_id = request.args.get('customer_id')
    ip = request.remote_addr
    logger.info(f"TRANSACTIONS_QUERY: ip={ip} customer_id={customer_id}")

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Service unavailable"}), 503

    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        if customer_id:
            cur.execute(
                """SELECT t.*, c.full_name
                   FROM transactions t
                   JOIN customers c ON t.customer_id = c.id
                   WHERE t.customer_id = %s
                   ORDER BY t.created_at DESC LIMIT 50""",
                (customer_id,)
            )
        else:
            cur.execute(
                """SELECT * FROM transactions
                   ORDER BY created_at DESC LIMIT 100"""
            )

        transactions = cur.fetchall()
        return jsonify({
            "status": "success",
            "count": len(transactions),
            "data": [dict(t) for t in transactions]
        }), 200

    except Exception as e:
        logger.error(f"TRANSACTIONS_ERROR: {str(e)}")
        return jsonify({"error": "Internal error"}), 500
    finally:
        conn.close()


@app.route('/api/stats', methods=['GET'])
def get_stats():
    """
    Estadísticas generales del sistema.
    Usado por Grafana para mostrar métricas del negocio.
    """
    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Service unavailable"}), 503

    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM customers WHERE account_status='active'")
        active_customers = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM transactions WHERE created_at > NOW() - INTERVAL '24 hours'")
        daily_transactions = cur.fetchone()[0]

        cur.execute("SELECT SUM(balance) FROM customers WHERE account_status='active'")
        total_balance = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM auth_logs WHERE success=false AND attempted_at > NOW() - INTERVAL '1 hour'")
        failed_logins = cur.fetchone()[0]

        return jsonify({
            "active_customers": active_customers,
            "daily_transactions": daily_transactions,
            "total_balance_managed": float(total_balance or 0),
            "failed_logins_last_hour": failed_logins,
            "timestamp": datetime.now().isoformat()
        }), 200

    except Exception as e:
        logger.error(f"STATS_ERROR: {str(e)}")
        return jsonify({"error": "Internal error"}), 500
    finally:
        conn.close()


# ──────────────────────────────────────────────
# PUNTO DE ENTRADA
# Gunicorn en producción, Flask dev server en debug
# ──────────────────────────────────────────────
if __name__ == '__main__':
    logger.info("🏦 Nexus Fintech API iniciando...")
    logger.info("⚠️  MODO LABORATORIO: Vulnerabilidades activas para SOC training")
    app.run(
        host='0.0.0.0',
        port=8080,
        debug=False
    )
