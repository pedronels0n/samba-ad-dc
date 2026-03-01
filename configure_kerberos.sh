#!/bin/bash
# configure_kerberos.sh - Configura o Kerberos para o domínio

source "$(dirname "$0")/common.sh"

# Verifica root
check_root

# Pega o nome do domínio (ex: exemplo.local)
DOMAIN=$(dialog --stdout --title "Configuração Kerberos" \
    --inputbox "Digite o nome do domínio (ex: exemplo.local):" 8 50)
if [ -z "$DOMAIN" ]; then
    error_exit "Domínio não informado."
fi

# Converte para maiúsculas (realm)
REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

# Define o servidor DNS (padrão é o próprio host)
cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    $REALM = {
        kdc = $(hostname -f)
        admin_server = $(hostname -f)
    }

[domain_realm]
    .$(echo "$DOMAIN" | sed 's/^\.//') = $REALM
    $(echo "$DOMAIN" | sed 's/^\.//') = $REALM
EOF

log "Arquivo /etc/krb5.conf gerado para o domínio $DOMAIN."
info_box "Kerberos configurado para o domínio:\n$DOMAIN\nRealm: $REALM"