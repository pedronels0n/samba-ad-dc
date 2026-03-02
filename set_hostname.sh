#!/bin/bash
# set_hostname.sh - Configura o hostname do sistema e atualiza /etc/hosts

source "$(dirname "$0")/common.sh"

# Verifica root
check_root

# Obtém o FQDN desejado (ex: dc1.pmlf.corp)
exec 3>&1
FQDN=$(dialog --stdout --title "Configuração do Hostname" \
    --inputbox "Digite o nome totalmente qualificado (FQDN) do servidor,\nexemplo: dc1.pmlf.corp" 10 50)
if [ -z "$FQDN" ]; then
    error_exit "Hostname não informado."
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

# Backup do /etc/hosts
cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d%H%M%S)

# Remove qualquer linha que contenha o hostname curto ou FQDN (para evitar duplicatas)
sed -i "/$HOSTNAME_SHORT/d" /etc/hosts
sed -i "/$FQDN/d" /etc/hosts

# Adiciona a nova entrada. Vamos usar o IP 127.0.1.1 (padrão Debian/Ubuntu para hostname)
# Se o sistema usar outro IP, isso pode ser ajustado posteriormente.
echo "127.0.1.1 $FQDN $HOSTNAME_SHORT" >> /etc/hosts

log "Arquivo /etc/hosts atualizado."
info_box "Hostname configurado para:\n$FQDN\nDomínio: $DOMAIN"