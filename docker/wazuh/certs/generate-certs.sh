#!/bin/bash
# ============================================================
# WATCHTOWER SOC PLATFORM v3.0
# Script: generate-certs.sh
# Descripción: Genera certificados TLS para todos los
#              componentes de Wazuh usando OpenSSL
# ============================================================

set -e  # Si cualquier comando falla, el script se detiene

CERTS_DIR="$(dirname "$0")"
cd "$CERTS_DIR"

echo "🔐 Generando certificados TLS para Wazuh..."
echo ""

# ──────────────────────────────────────────────
# PASO 1: Crear la Autoridad Certificadora Raíz (CA)
# 
# ¿Qué es una CA? Es quien "firma" y valida todos los
# demás certificados. Es como el Registro Civil que
# emite y valida los documentos de identidad.
# 
# -newkey rsa:2048  → Clave RSA de 2048 bits (segura)
# -x509             → Genera directamente el certificado
# -days 3650        → Válido por 10 años (para el lab)
# -nodes            → Sin contraseña en la clave privada
# ──────────────────────────────────────────────
echo "1/4 Creando Autoridad Certificadora (Root CA)..."
openssl req -x509 -newkey rsa:2048 \
  -keyout root-ca.key \
  -out root-ca.pem \
  -days 3650 -nodes \
  -subj "/C=US/ST=California/L=Santa Clara/O=Wazuh/OU=SOC/CN=root-ca"

echo "     ✅ root-ca.key y root-ca.pem creados"
echo ""

# ──────────────────────────────────────────────
# FUNCIÓN para generar certificados de componentes
# Recibe: nombre del componente (ej: wazuh.indexer)
# Genera: nombre.key y nombre.pem firmados por la CA
# ──────────────────────────────────────────────
generate_component_cert() {
  local COMPONENT=$1
  echo "Generando certificado para: $COMPONENT"
  
  # Paso A: Crear la clave privada del componente
  openssl genrsa -out "${COMPONENT}.key" 2048

  # Paso B: Crear una solicitud de certificado (CSR)
  # CSR = Certificate Signing Request
  # Es como llenar el formulario para pedir el carné
  openssl req -new \
    -key "${COMPONENT}.key" \
    -out "${COMPONENT}.csr" \
    -subj "/C=US/ST=California/L=Santa Clara/O=Wazuh/OU=SOC/CN=${COMPONENT}"

  # Paso C: La CA firma el CSR y emite el certificado
  # Es como el Registro Civil aprobando y sellando el carné
  openssl x509 -req \
    -in "${COMPONENT}.csr" \
    -CA root-ca.pem \
    -CAkey root-ca.key \
    -CAcreateserial \
    -out "${COMPONENT}.pem" \
    -days 3650 \
    -extfile <(printf "subjectAltName=DNS:%s,IP:127.0.0.1" "$COMPONENT")

  # Limpiamos el CSR (ya no lo necesitamos)
  rm "${COMPONENT}.csr"
  
  echo "     ✅ ${COMPONENT}.key y ${COMPONENT}.pem creados"
  echo ""
}

# ──────────────────────────────────────────────
# PASO 2, 3, 4: Generar cert para cada componente
# ──────────────────────────────────────────────
echo "2/4 Creando certificado para Wazuh Indexer..."
generate_component_cert "wazuh.indexer"

echo "3/4 Creando certificado para Wazuh Manager..."
generate_component_cert "wazuh.manager"

echo "4/4 Creando certificado para Wazuh Dashboard..."
generate_component_cert "wazuh.dashboard"

# ──────────────────────────────────────────────
# PASO 5: Certificado admin (para securityadmin.sh)
# Este certificado especial permite ejecutar operaciones
# administrativas en el Indexer como aplicar configuraciones
# de seguridad y crear usuarios
# ──────────────────────────────────────────────
echo "5/5 Creando certificado admin..."
openssl genrsa -out admin.key 2048
openssl req -new \
  -key admin.key \
  -out admin.csr \
  -subj "/C=US/ST=California/L=Santa Clara/O=Wazuh/OU=SOC/CN=admin"
openssl x509 -req \
  -in admin.csr \
  -CA root-ca.pem \
  -CAkey root-ca.key \
  -CAcreateserial \
  -out admin.pem \
  -days 3650
rm admin.csr
echo "     ✅ admin.key y admin.pem creados"
echo ""

# ──────────────────────────────────────────────
# PASO 6: Ajustar permisos
# Los certificados deben ser legibles pero no
# modificables por otros usuarios (seguridad básica)
# 600 = solo el dueño puede leer y escribir
# ──────────────────────────────────────────────
chmod 600 *.key
chmod 644 *.pem

echo "✅ Todos los certificados generados exitosamente"
echo ""
echo "Archivos creados:"
ls -la *.pem *.key 2>/dev/null
