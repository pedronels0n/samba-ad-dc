#!/bin/bash
# distribute_ca.sh - Instala o certificado da CA no repositório de confiança do sistema

source "$(dirname "$0")/common.sh"

check_root

# utiliza CA_DIR definido em common.sh ou padrão
CA_DIR="${CA_DIR:-/root/samba-ca}"
CA_CERT="$CA_DIR/ca.crt"

if [ ! -f "$CA_CERT" ]; then
    error_exit "Certificado da CA não encontrado. Execute primeiro o script setup_ca.sh."
fi

# Detecta a distribuição
if [ -d /usr/local/share/ca-certificates/ ]; then
    # Debian/Ubuntu
    cp "$CA_CERT" /usr/local/share/ca-certificates/samba-ca.crt
    update-ca-certificates >> "$LOG_FILE" 2>&1
    log "CA instalada no sistema (Debian/Ubuntu)."
elif [ -d /etc/pki/ca-trust/source/anchors/ ]; then
    # RHEL/CentOS/Fedora
    cp "$CA_CERT" /etc/pki/ca-trust/source/anchors/samba-ca.crt
    update-ca-trust >> "$LOG_FILE" 2>&1
    log "CA instalada no sistema (RHEL)."
else
    error_exit "Sistema não suportado para instalação automática da CA."
fi

info_box "Certificado da CA instalado no sistema.\nAgora todos os serviços com certificados assinados por esta CA serão confiáveis."