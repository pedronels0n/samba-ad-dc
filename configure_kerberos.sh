#!/bin/bash
# configure_kerberos.sh - Configura o Kerberos para o domínio

source "$(dirname "$0")/common.sh"

# Verifica root
check_root
check_prereqs dialog

# Pega o nome do domínio (ex: exemplo.local)
DOMAIN=$(dialog --stdout --title "Configuração Kerberos" \
    --inputbox "Digite o nome do domínio (ex: exemplo.local):" 8 50)
if [ -z "$DOMAIN" ]; then
    error_exit "Domínio não informado."
fi

# Valida o domínio (deve conter ao menos um ponto)
if ! [[ "$DOMAIN" =~ \. ]]; then
    error_exit "Domínio inválido. Deve conter ao menos um ponto (ex: exemplo.local)"
fi

# Converte para maiúsculas (realm)
REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

# Pega o FQDN do servidor (normalmente deve ser conhecido neste ponto)
FQDN=$(hostname -f)
if [ -z "$FQDN" ] || [ "$FQDN" = "localhost" ]; then
    FQDN=$(dialog --stdout --title "FQDN do Servidor KDC" \
        --inputbox "Digite o FQDN do servidor (ex: dc1.exemplo.local):" 8 50)
    if [ -z "$FQDN" ]; then
        error_exit "FQDN do servidor não informado."
    fi
fi

log "Configurando Kerberos para domínio: $DOMAIN (realm: $REALM)"
log "Servidor KDC: $FQDN"

# Faz backup do krb5.conf atual caso exista
if [ -f /etc/krb5.conf ]; then
    cp /etc/krb5.conf /etc/krb5.conf.bak.$(date +%Y%m%d%H%M%S)
fi

# Define o servidor DNS (padrão é o próprio host)
cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 des-cbc-md5
    default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 des-cbc-md5

[realms]
    $REALM = {
        kdc = $FQDN
        admin_server = $FQDN
        default_domain = $DOMAIN
    }

[domain_realm]
    .$(echo "$DOMAIN" | sed 's/^\.//') = $REALM
    $(echo "$DOMAIN" | sed 's/^\.//') = $REALM

[logging]
    default = FILE:/var/log/krb5libs.log
    kdc = FILE:/var/log/krb5kdc.log
    admin_server = FILE:/var/log/kadmind.log
EOF

log "Arquivo /etc/krb5.conf gerado para o domínio $DOMAIN."
info_box "Kerberos configurado:\n\
Domínio: $DOMAIN\n\
Realm (maiúscula): $REALM\n\
Servidor KDC: $FQDN"