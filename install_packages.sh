#!/bin/bash
# install_packages.sh - Instala os pacotes para o Samba DC

# Carrega funções comuns
source "$(dirname "$0")/common.sh"

# Verifica root
check_root

# Atualiza lista de pacotes e instala
log "Atualizando lista de pacotes..."
apt-get update >> "$LOG_FILE" 2>&1 || error_exit "Falha ao atualizar pacotes."

log "Instalando pacotes: samba, krb5-config, winbind, etc."
# Define opções para evitar prompts interativos do Kerberos
export DEBIAN_FRONTEND=noninteractive
apt-get install -y samba krb5-config krb5-user winbind libpam-winbind libnss-winbind \
    dnsutils net-tools acl attr >> "$LOG_FILE" 2>&1 || error_exit "Falha na instalação dos pacotes."

log "Pacotes instalados com sucesso."
info_box "Pacotes instalados com sucesso:\n- samba\n- krb5-*\n- winbind\n- dnsutils\n- acl/attr"