#!/bin/bash
# set_resolv.sh - Configura o /etc/resolv.conf com domínio e nameservers

source "$(dirname "$0")/common.sh"

# Verifica root
check_root

# Detecta se o sistema usa systemd-resolved ou resolvconf, mas vamos editar diretamente com aviso.
# Muitos sistemas têm o resolv.conf gerenciado, então faremos backup e substituiremos, mas avisaremos.

# Solicita domínio de pesquisa
exec 3>&1
DOMAIN=$(dialog --stdout --title "Domínio de Pesquisa" \
    --inputbox "Digite o domínio de pesquisa (ex: exemplo.local):" 8 50)
[ -z "$DOMAIN" ] && error_exit "Domínio não informado."

# Solicita nameservers
DNS1=$(dialog --stdout --title "Nameserver Primário" \
    --inputbox "Digite o primeiro nameserver:" 8 50)
[ -z "$DNS1" ] && error_exit "Nameserver primário não informado."

DNS2=$(dialog --stdout --title "Nameserver Secundário (opcional)" \
    --inputbox "Digite o segundo nameserver (ou deixe em branco):" 8 50)

# Faz backup do resolv.conf atual
cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d%H%M%S)

# Cria novo resolv.conf
{
    echo "# Gerado por script de configuração Samba DC"
    echo "domain $DOMAIN"
    echo "search $DOMAIN"
    echo "nameserver $DNS1"
    [ -n "$DNS2" ] && echo "nameserver $DNS2"
} > /etc/resolv.conf

log "Arquivo /etc/resolv.conf atualizado."
info_box "resolv.conf configurado:\nDomínio: $DOMAIN\nNameservers: $DNS1 $DNS2\n\nAtenção: Se o sistema usar systemd-resolved ou outro gerenciador, esta configuração pode ser sobrescrita."