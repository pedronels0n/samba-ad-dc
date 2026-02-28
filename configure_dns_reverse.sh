#!/bin/bash
# configure_dns_reverse.sh - Configura zona reversa no DNS do Samba

source "$(dirname "$0")/common.sh"

check_root

# Obtém informações da rede
exec 3>&1
NETWORK=$(dialog --stdout --title "Rede para DNS Reverso" \
    --inputbox "Digite a rede no formato CIDR (ex: 192.168.1.0/24):" 8 50)
[ -z "$NETWORK" ] && error_exit "Rede não informada."

# Converte a rede para zona reversa (ex: 1.168.192.in-addr.arpa)
IP_PREFIX=$(echo "$NETWORK" | cut -d/ -f1 | awk -F. '{print $3"."$2"."$1}')
ZONE="${IP_PREFIX}.in-addr.arpa"

# Verifica se a zona já existe
if samba-tool dns zoneinfo $(hostname) "$ZONE" >/dev/null 2>&1; then
    confirm_box "A zona reversa $ZONE já existe. Deseja recriá-la?"
    if [ $? -eq 0 ]; then
        samba-tool dns zone delete $(hostname) "$ZONE" -U Administrator >> "$LOG_FILE" 2>&1
    else
        info_box "Operação cancelada."
        exit 0
    fi
fi

# Cria a zona
log "Criando zona reversa $ZONE..."
samba-tool dns zonecreate $(hostname) "$ZONE" -U Administrator >> "$LOG_FILE" 2>&1
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
samba-tool dns add $(hostname) "$ZONE" "$LAST_OCTET" PTR "$HOSTNAME_FQDN" -U Administrator >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    info_box "Zona reversa $ZONE criada e registro PTR adicionado para $HOSTNAME_FQDN."
else
    error_exit "Falha ao adicionar registro PTR."
fi