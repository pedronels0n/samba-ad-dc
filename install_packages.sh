#!/bin/bash
# install_packages.sh - Instala os pacotes para o Samba DC

# Carrega funções comuns
source "$(dirname "$0")/common.sh"

# Verifica root
check_root

# Atualiza lista de pacotes e instala
log "Atualizando lista de pacotes..."
apt-get update >> "$LOG_FILE" 2>&1 || error_exit "Falha ao atualizar pacotes."

log "Instalando pacotes: samba, krb5-config, winbind, chrony, rsyslog, smbclient e utilitários..."

# Define opções para evitar prompts interativos do Kerberos e outros
export DEBIAN_FRONTEND=noninteractive

# Instala os pacotes essenciais para o Samba DC
apt-get install -y \
    samba \
    krb5-config \
    krb5-user \
    winbind \
    libpam-winbind \
    libnss-winbind \
    chrony \
    rsyslog \
    smbclient \
    dnsutils \
    net-tools \
    acl \
    attr \
    >> "$LOG_FILE" 2>&1 || error_exit "Falha na instalação dos pacotes."

# Verifica se chrony foi instalado e inicia o serviço
if systemctl list-unit-files | grep -q chrony; then
    systemctl enable chrony --now >> "$LOG_FILE" 2>&1
    log "Serviço chrony ativado e iniciado."
else
    log "AVISO: chrony não encontrado após instalação. Verifique."
fi

# rsyslog geralmente já está ativo, mas garantimos
systemctl enable rsyslog --now >> "$LOG_FILE" 2>&1 || true

log "Pacotes instalados com sucesso."

info_box "Pacotes instalados com sucesso:\n\
- samba (servidor AD DC)\n\
- krb5-* (Kerberos)\n\
- winbind (integração)\n\
- chrony (sincronização de tempo)\n\
- rsyslog (logging)\n\
- smbclient (cliente para testes)\n\
- dnsutils, net-tools, acl, attr"