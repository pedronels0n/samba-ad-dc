#!/bin/bash
# install_packages.sh - Instala os pacotes para o Samba DC (modo interativo para krb5-config)

source "$(dirname "$0")/common.sh"

check_root

log "Atualizando lista de pacotes..."
apt-get update >> "$LOG_FILE" 2>&1 || error_exit "Falha ao atualizar pacotes."

log "Instalando pacotes: samba, krb5-config, winbind, chrony, rsyslog, smbclient e utilitários..."

# NÃO definir DEBIAN_FRONTEND=noninteractive para permitir que o krb5-config faça perguntas
# O -y apenas confirma a instalação, mas as configurações dos pacotes (debconf) serão interativas.
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
    ldb-tools \
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
- krb5-* (Kerberos - configure o realm quando solicitado)\n\
- winbind (integração)\n\
- chrony (sincronização de tempo)\n\
- rsyslog (logging)\n\
- smbclient (cliente para testes)\n\
- dnsutils, net-tools, acl, attr"