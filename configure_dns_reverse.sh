#!/bin/bash
# configure_dns_reverse.sh - Configura zona reversa no DNS do Samba

source "$(dirname "$0")/common.sh"

check_root
check_prereqs dialog samba-tool ip awk hostname grep systemctl

# Arquivo de configuração do Samba
SMB_CONF="/etc/samba/smb.conf"

# Flag para controlar se o Samba foi pausado
SAMBA_PAUSED=false

# Trap para garantir que o Samba seja retomado em caso de erro
cleanup_samba() {
    if [ "$SAMBA_PAUSED" = true ]; then
        log "Retomando o serviço Samba..."
        systemctl start samba >/dev/null 2>&1 || true
    fi
}
trap cleanup_samba EXIT

# Função para pausar o Samba
pause_samba() {
    log "Pausando o serviço Samba..."
    systemctl stop samba || error_exit "Falha ao parar o serviço Samba."
    SAMBA_PAUSED=true
    sleep 2
    log "Samba pausado com sucesso."
}

# Função para retomar o Samba
resume_samba() {
    log "Retomando o serviço Samba..."
    systemctl start samba || error_exit "Falha ao iniciar o serviço Samba."
    SAMBA_PAUSED=false
    log "Samba retomado com sucesso."
}



# Função para mostrar configurações atuais
show_current_config() {
    clear
    log "Configurações atuais do smb.conf [global]:"
    echo "=========================================="
    sed -n '/^\[global\]/,/^\[/p' "$SMB_CONF" | head -n -1
    echo "=========================================="
}

# ========== VERIFICAÇÃO INICIAL ==========
# Verifica se o smb.conf existe
if [ ! -f "$SMB_CONF" ]; then
    error_exit "Arquivo $SMB_CONF não encontrado. Verifique a instalação do Samba."
fi

# Mostra configuração atual
show_current_config

log "Iniciando configuração de DNS Reverso..."

# Pausa o Samba
pause_samba

# ==========================================

# Obtém informações da rede
exec 3>&1
NETWORK=$(dialog --stdout --title "Rede para DNS Reverso" \
    --inputbox "Digite a rede no formato CIDR (ex: 192.168.1.0/24):" 8 50)
[ -z "$NETWORK" ] && error_exit "Rede não informada."
# validação básica CIDR
if ! [[ "$NETWORK" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    error_exit "Formato de rede inválido. Use algo como 192.168.1.0/24."
fi

# Converte a rede para zona reversa (ex: 1.168.192.in-addr.arpa)
IP_PREFIX=$(echo "$NETWORK" | cut -d/ -f1 | awk -F. '{print $3"."$2"."$1}')
ZONE="${IP_PREFIX}.in-addr.arpa"

# Verifica se a zona já existe
HOST=$(hostname -f)
if samba-tool -U Administrator dns zoneinfo "$HOST" "$ZONE"; then
    confirm_box "A zona reversa $ZONE já existe. Deseja recriá-la?"
    if [ $? -eq 0 ]; then
        samba-tool dns zone delete "$HOST" "$ZONE" -U Administrator
    else
        info_box "Operação cancelada."
        exit 0
    fi
fi

# Cria a zona
log "Criando zona reversa $ZONE..."
samba-tool -U Administrator dns zonecreate "$HOST" "$ZONE"
if [ $? -ne 0 ]; then
    error_exit "Falha ao criar zona reversa."
fi

# Obtém o IP do servidor (assumindo que a interface configurada tem o IP)
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)
if [ -z "$SERVER_IP" ]; then
    error_exit "Não foi possível determinar o IP do servidor."
fi

# Extrai o último octeto e adiciona registro PTR
LAST_OCTET=$(echo "$SERVER_IP" | awk -F. '{print $4}')
HOSTNAME_FQDN=$(hostname -f)

log "Adicionando registro PTR para $HOSTNAME_FQDN ($SERVER_IP)..."
samba-tool dns add "$HOST" "$ZONE" "$LAST_OCTET" PTR "$HOSTNAME_FQDN" -U Administrator
if [ $? -eq 0 ]; then
    log "Registro PTR adicionado com sucesso!"
    # Retoma o Samba
    resume_samba
    info_box "Zona reversa $ZONE criada com sucesso!\nRegistro PTR adicionado para $HOSTNAME_FQDN ($SERVER_IP)"
    log "Configuração concluída com sucesso!"
else
    # Retoma o Samba mesmo em caso de erro
    resume_samba
    error_exit "Falha ao adicionar registro PTR."
fi