#!/bin/bash
# configure_dns_reverse.sh - Configura zona reversa no DNS do Samba

source "$(dirname "$0")/common.sh"

check_root
check_prereqs dialog samba-tool ip awk hostname

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
if samba-tool -U Administrator dns zoneinfo "$HOST" "$ZONE" >/dev/null 2>&1; then
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
samba-tool -U Administrator dns add "$HOST" "$ZONE" "$LAST_OCTET" PTR "$HOSTNAME_FQDN"
if [ $? -eq 0 ]; then
    info_box "Zona reversa $ZONE criada e registro PTR adicionado para $HOSTNAME_FQDN."
else
    error_exit "Falha ao adicionar registro PTR."
fi