#!/bin/bash
# set_resolv.sh - Configura o /etc/resolv.conf com domínio e nameservers

source "$(dirname "$0")/common.sh"

# Verifica root
check_root
check_prereqs dialog cp

# Detecta se o sistema usa systemd-resolved ou resolvconf, mas vamos editar diretamente com aviso.
# Muitos sistemas têm o resolv.conf gerenciado, então faremos backup e substituiremos, mas avisaremos.

# Solicita domínio de pesquisa (exemplo adaptado para pmlf.corp)
exec 3>&1
DOMAIN=$(dialog --stdout --title "Domínio de Pesquisa" \
    --inputbox "Digite o domínio de pesquisa (ex: pmlf.corp):" 8 50)
[ -z "$DOMAIN" ] && error_exit "Domínio não informado."
# formato simples: deve conter ao menos um ponto e apenas caracteres aceitáveis
if ! [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error_exit "Domínio de pesquisa parece inválido."
fi

# IMPORTANTE: Para um AD DC funcionar corretamente, o DNS primário DEVE apontar para este servidor (127.0.0.1)
info_box "IMPORTANTE:\nPara o Active Directory funcionar,\no DNS primário deve ser este servidor (127.0.0.1).\nIsso permite que clientes resolvam SRV records corretamente."

# Solicita nameservers
DNS1=$(dialog --stdout --title "Nameserver Primário" \
    --inputbox "Digite o primeiro nameserver (RECOMENDADO: 127.0.0.1 para AD DC):" 8 50)
[ -z "$DNS1" ] && error_exit "Nameserver primário não informado."
if ! [[ "$DNS1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error_exit "Nameserver primário inválido."
fi

DNS2=$(dialog --stdout --title "Nameserver Secundário (opcional)" \
    --inputbox "Digite o segundo nameserver (ou deixe em branco):" 8 50)
if [ -n "$DNS2" ] && ! [[ "$DNS2" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error_exit "Nameserver secundário inválido."
fi

DNS3=$(dialog --stdout --title "Nameserver Terciário (opcional)" \
    --inputbox "Digite o terceiro nameserver (ou deixe em branco):" 8 50)
if [ -n "$DNS3" ] && ! [[ "$DNS3" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error_exit "Nameserver terciário inválido."
fi

# Faz backup do resolv.conf atual
cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d%H%M%S)

# Cria novo resolv.conf
{
    echo "# Gerado por script de configuração Samba DC"
    echo "domain $DOMAIN"
    echo "search $DOMAIN"
    echo "nameserver $DNS1"
    [ -n "$DNS2" ] && echo "nameserver $DNS2"
    [ -n "$DNS3" ] && echo "nameserver $DNS3"
} > /etc/resolv.conf

log "Arquivo /etc/resolv.conf atualizado."
info_box "resolv.conf configurado:\nDomínio: $DOMAIN\nNameservers: $DNS1 $DNS2 $DNS3\n\nAtenção: Se o sistema usar systemd-resolved ou outro gerenciador, esta configuração pode ser sobrescrita."