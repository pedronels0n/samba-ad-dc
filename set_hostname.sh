#!/bin/bash
# set_hostname.sh - Configura o hostname do sistema e atualiza /etc/hosts

source "$(dirname "$0")/common.sh"

# Verifica root
check_root
check_prereqs hostnamectl dialog sed grep

# Obtém o FQDN desejado (ex: dc1.pmlf.corp)
exec 3>&1
FQDN=$(dialog --stdout --title "Configuração do Hostname" \
    --inputbox "Digite o nome totalmente qualificado (FQDN) do servidor,\nexemplo: dc1.pmlf.corp" 10 50)
if [ -z "$FQDN" ]; then
    error_exit "Hostname não informado."
fi
# validação simples de FQDN
if ! [[ "$FQDN" =~ ^[A-Za-z0-9][-A-Za-z0-9]*\.[A-Za-z0-9.-]+$ ]]; then
    error_exit "FQDN inválido. Certifique-se de incluir um domínio, ex: dc1.pmlf.corp"
fi

# Extrai o hostname curto (primeiro componente)
HOSTNAME_SHORT=$(echo "$FQDN" | cut -d. -f1)
DOMAIN=$(echo "$FQDN" | cut -d. -f2-)

if [ -z "$DOMAIN" ]; then
    error_exit "O FQDN deve incluir o domínio (ex: dc1.pmlf.corp)."
fi

# Define o hostname
log "Configurando hostname para $FQDN (curto: $HOSTNAME_SHORT)"
hostnamectl set-hostname "$FQDN" || error_exit "Falha ao configurar hostname com hostnamectl."

# Atualiza /etc/hosts para incluir o FQDN e o shortname apontando para o IP local
# Primeiro, obtém o IP atual (pode ser o do loopback? Melhor pegar o IP da interface principal)
# Vamos usar uma abordagem: comentar qualquer linha com o mesmo nome e adicionar a nova.
# Mas para simplificar, vamos substituir a entrada 127.0.1.1 que muitas distribuições usam.
# Se existir 127.0.1.1, substituímos; senão, adicionamos.

# Tenta obter o IP real da primeira interface não-loopback
IP_REAL=$(ip -o route get 1 | awk '{print $7;exit}')
if [ -z "$IP_REAL" ] || [ "$IP_REAL" = "127.0.0.1" ]; then
    # Se não conseguir, usa 127.0.1.1 como fallback (útil apenas para localhost)
    log "AVISO: Não foi detectado IP real. Usando 127.0.1.1 no /etc/hosts como fallback."
    log "Execute 'set_network.sh' primeiro para configurar IP estático e /etc/hosts corretamente."
    IP_REAL="127.0.1.1"
else
    log "IP detectado para $FQDN: $IP_REAL"
fi

# Backup do /etc/hosts
cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d%H%M%S)

# Remove qualquer linha que contenha o hostname curto ou FQDN (para evitar duplicatas)
sed -i "/$HOSTNAME_SHORT/d" /etc/hosts
sed -i "/$FQDN/d" /etc/hosts

# Adiciona a nova entrada com o IP detectado
echo "$IP_REAL $FQDN $HOSTNAME_SHORT" >> /etc/hosts

log "Arquivo /etc/hosts atualizado com IP: $IP_REAL"
info_box "Hostname configurado para:\n$FQDN\nDomínio: $DOMAIN\nIP no /etc/hosts: $IP_REAL\n\nDica: Se o IP aparecer como 127.0.1.1, execute primeiro set_network.sh para configurar IP estático."