#!/bin/bash
# info_wildcard.sh - Exibe informações do certificado wildcard

source "$(dirname "$0")/common.sh"

# utiliza diretório padrão definido em common.sh
CA_DIR="${CA_DIR:-/root/samba-ca}"
WILDCARD_CERT="$CA_DIR/wildcard.crt"

if [ ! -f "$WILDCARD_CERT" ]; then
    info_box "Certificado wildcard ainda não foi gerado.\nExecute primeiro a opção 14 (Criar CA)."
    exit 0
fi

# Extrai informações relevantes
SUBJECT=$(openssl x509 -in "$WILDCARD_CERT" -noout -subject)
ISSUER=$(openssl x509 -in "$WILDCARD_CERT" -noout -issuer)
EXPIRATION=$(openssl x509 -in "$WILDCARD_CERT" -noout -enddate | cut -d= -f2)
VALID_FROM=$(openssl x509 -in "$WILDCARD_CERT" -noout -startdate | cut -d= -f2)
SERIAL=$(openssl x509 -in "$WILDCARD_CERT" -noout -serial | cut -d= -f2)
FINGERPRINT=$(openssl x509 -in "$WILDCARD_CERT" -noout -fingerprint -sha256 | cut -d= -f2)

# Formata a mensagem
MSG="Certificado Wildcard: $WILDCARD_CERT\n\n"
MSG+="Assunto (Subject): $SUBJECT\n"
MSG+="Emissor (Issuer): $ISSUER\n"
MSG+="Válido de: $VALID_FROM\n"
MSG+="Válido até: $EXPIRATION\n"
MSG+="Serial: $SERIAL\n"
MSG+="Fingerprint SHA256: $FINGERPRINT\n\n"
MSG+="Localização: $CA_DIR"

info_box "$MSG"