-- ============================================================
-- WATCHTOWER SOC PLATFORM v3.0
-- Archivo: setup_db.sql
-- Descripción: Schema y datos de Nexus Fintech
-- Contiene: 1,000 registros de clientes PII simulados
-- AVISO: Datos completamente ficticios para uso educativo
-- ============================================================

-- Creamos la tabla principal de clientes
-- Esta es la "joya de la corona" que los atacantes quieren robar
CREATE TABLE IF NOT EXISTS customers (
    id              SERIAL PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    email           VARCHAR(100) UNIQUE NOT NULL,
    phone           VARCHAR(20),
    card_number     VARCHAR(19) NOT NULL,  -- Formato: XXXX-XXXX-XXXX-XXXX
    card_cvv        VARCHAR(4)  NOT NULL,
    card_expiry     VARCHAR(7)  NOT NULL,  -- Formato: MM/YYYY
    balance         DECIMAL(12,2) DEFAULT 0.00,
    account_status  VARCHAR(20) DEFAULT 'active',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login      TIMESTAMP
);

-- Tabla de transacciones
-- Registra cada movimiento de dinero
CREATE TABLE IF NOT EXISTS transactions (
    id              SERIAL PRIMARY KEY,
    customer_id     INTEGER REFERENCES customers(id),
    amount          DECIMAL(12,2) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,  -- 'credit' o 'debit'
    description     VARCHAR(200),
    ip_address      VARCHAR(45),           -- IP desde donde se hizo
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de intentos de autenticación
-- CRÍTICA para el SIEM: aquí detectamos brute force
CREATE TABLE IF NOT EXISTS auth_logs (
    id              SERIAL PRIMARY KEY,
    username        VARCHAR(100),
    ip_address      VARCHAR(45) NOT NULL,
    success         BOOLEAN NOT NULL,
    user_agent      VARCHAR(500),
    attempted_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de usuarios del sistema (empleados del banco)
CREATE TABLE IF NOT EXISTS system_users (
    id              SERIAL PRIMARY KEY,
    username        VARCHAR(50) UNIQUE NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    role            VARCHAR(30) DEFAULT 'analyst',  -- admin, analyst, readonly
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ──────────────────────────────────────────────
-- INSERTAR USUARIOS DEL SISTEMA
-- Credenciales débiles intencionales para el lab
-- ──────────────────────────────────────────────
INSERT INTO system_users (username, password_hash, role) VALUES
('admin',    md5('admin123'),    'admin'),
('analyst1', md5('analyst2024'), 'analyst'),
('readonly', md5('readonly'),    'readonly');

-- ──────────────────────────────────────────────
-- GENERAR 1,000 CLIENTES CON DATOS PII
-- Usamos funciones de PostgreSQL para generar datos
-- realistas sin necesidad de insertar 1,000 líneas
-- ──────────────────────────────────────────────
INSERT INTO customers (
    full_name,
    email,
    phone,
    card_number,
    card_cvv,
    card_expiry,
    balance,
    account_status,
    last_login
)
SELECT
    -- Nombre: combinación de nombres y apellidos latinos
    (ARRAY['Carlos','María','José','Ana','Luis','Carmen',
            'Miguel','Laura','Juan','Sofia','Diego','Valentina',
            'Andrés','Isabella','Pablo','Camila','Jorge','Daniela',
            'Roberto','Fernanda','Ricardo','Gabriela','Fernando',
            'Patricia','Eduardo','Monica','Alejandro','Natalia']
    )[floor(random()*28+1)::int]
    || ' ' ||
    (ARRAY['García','Rodríguez','López','Martínez','González',
            'Pérez','Sánchez','Ramírez','Torres','Flores',
            'Rivera','Gómez','Díaz','Cruz','Morales',
            'Reyes','Ortiz','Gutierrez','Chavez','Ramos',
            'Mendoza','Ruiz','Alvarez','Jimenez','Moreno']
    )[floor(random()*25+1)::int],

    -- Email único basado en el ID del registro
    'cliente' || generate_series || '@nexusfintech.com',

    -- Teléfono formato latinoamericano
    '+51 9' || floor(random()*9+1)::text ||
    floor(random()*10000000+10000000)::text,

    -- Número de tarjeta formato XXXX-XXXX-XXXX-XXXX
    -- Empieza con 4 (Visa) o 5 (Mastercard)
    (ARRAY['4','5'])[floor(random()*2+1)::int] ||
    floor(random()*999+100)::text || '-' ||
    floor(random()*9000+1000)::text || '-' ||
    floor(random()*9000+1000)::text || '-' ||
    floor(random()*9000+1000)::text,

    -- CVV de 3 dígitos
    floor(random()*900+100)::text,

    -- Fecha de expiración (entre 2025 y 2029)
    floor(random()*12+1)::text || '/' ||
    (2025 + floor(random()*5)::int)::text,

    -- Balance entre S/. 100 y S/. 50,000
    round((random() * 49900 + 100)::numeric, 2),

    -- 95% activos, 5% suspendidos
    CASE WHEN random() > 0.05 THEN 'active' ELSE 'suspended' END,

    -- Último login en los últimos 30 días
    NOW() - (random() * interval '30 days')

FROM generate_series(1, 1000);

-- ──────────────────────────────────────────────
-- INSERTAR TRANSACCIONES DE EJEMPLO
-- 5,000 transacciones históricas para dar
-- contexto al análisis forense
-- ──────────────────────────────────────────────
INSERT INTO transactions (
    customer_id,
    amount,
    transaction_type,
    description,
    ip_address
)
SELECT
    floor(random()*1000+1)::int,
    round((random() * 5000 + 10)::numeric, 2),
    (ARRAY['credit','debit'])[floor(random()*2+1)::int],
    (ARRAY[
        'Transferencia bancaria',
        'Pago de servicio',
        'Compra en línea',
        'Retiro ATM',
        'Depósito en efectivo',
        'Pago de tarjeta',
        'Transferencia internacional'
    ])[floor(random()*7+1)::int],
    -- IPs simuladas (algunas serán "maliciosas" en los ataques)
    floor(random()*255+1)::text || '.' ||
    floor(random()*255+1)::text || '.' ||
    floor(random()*255+1)::text || '.' ||
    floor(random()*255+1)::text
FROM generate_series(1, 5000);

-- ──────────────────────────────────────────────
-- ÍNDICES para mejorar rendimiento de consultas
-- También ayuda a detectar patrones de acceso
-- anómalos (muchas consultas rápidas = exfiltración)
-- ──────────────────────────────────────────────
CREATE INDEX idx_customers_email    ON customers(email);
CREATE INDEX idx_customers_card     ON customers(card_number);
CREATE INDEX idx_transactions_cust  ON transactions(customer_id);
CREATE INDEX idx_transactions_date  ON transactions(created_at);
CREATE INDEX idx_auth_logs_ip       ON auth_logs(ip_address);
CREATE INDEX idx_auth_logs_date     ON auth_logs(attempted_at);

-- Confirmación de datos insertados
DO $$
BEGIN
    RAISE NOTICE '✅ Nexus Fintech DB inicializada:';
    RAISE NOTICE '   - Clientes PII: 1,000 registros';
    RAISE NOTICE '   - Transacciones: 5,000 registros';
    RAISE NOTICE '   - Usuarios sistema: 3 usuarios';
    RAISE NOTICE '   - Índices creados: 6';
END $$;
