#!/bin/bash
# renew_wildcard_cert.sh - Renova o certificado wildcard usando a CA existente
# Uso: agendar no cron (ex: a cada 6 meses) para renovar antes da expiração

source "$(dirname "$0")/common.sh"

check_root
check_prereqs openssl date cp mv chmod systemctl

DOMAIN=$(hostname -d)
FQDN=$(hostname -f)
# o common.sh já define CA_DIR padrão, mas garantimos a variável caso não tenha sido
CA_DIR="${CA_DIR:-/root/samba-ca}"
CERTS_DIR="${CERTS_DIR:-/etc/ssl/certs}"
PRIVATE_DIR="${PRIVATE_DIR:-/etc/ssl/private}"
CA_NAME="ca-${DOMAIN}"
WILDCARD_NAME="wildcard.${DOMAIN}"
CERT_FILE="$CERTS_DIR/${WILDCARD_NAME}.crt"
DAYS_BEFORE=60  # Renovar se faltar <= 60 dias

# Verifica se o certificado existe
if [ ! -f "$CERT_FILE" ]; then
    error_exit "Certificado wildcard não encontrado. Execute setup_ca.sh primeiro."
fi

# Verifica data de expiração
expiration_date=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
expiration_epoch=$(date -d "$expiration_date" +%s)
current_epoch=$(date +%s)
days_left=$(( (expiration_epoch - current_epoch) / 86400 ))

log "Certificado atual expira em: $expiration_date (faltam $days_left dias)"

if [ $days_left -le $DAYS_BEFORE ]; then
    log "Renovando certificado..."
    
    # Backup do certificado antigo
    BACKUP_DIR="$CA_DIR/backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp "$CERT_FILE" "$BACKUP_DIR/"
    cp "$PRIVATE_DIR/${WILDCARD_NAME}.key" "$BACKUP_DIR/"
    log "Backup dos arquivos atuais em $BACKUP_DIR"
    
    # Gera nova chave (opcional: pode reutilizar a mesma chave, mas é melhor gerar nova)
    openssl genrsa -out "$CA_DIR/${WILDCARD_NAME}.key.new" 2048 >> "$LOG_FILE" 2>&1
    
    # Cria novo CSR
    openssl req -new -key "$CA_DIR/${WILDCARD_NAME}.key.new" \
        -out "$CA_DIR/${WILDCARD_NAME}.csr.new" \
        -subj "/C=BR/ST=Sao Paulo/L=Sao Paulo/O=Empresa/OU=TI/CN=*.$DOMAIN/emailAddress=admin@$DOMAIN" \
        >> "$LOG_FILE" 2>&1
    
    # Usa o mesmo arquivo de extensões (ou recria)
    cat > "$CA_DIR/${WILDCARD_NAME}.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.$DOMAIN
DNS.2 = $FQDN
EOF
    
    # Assina com a CA
    openssl x509 -req -in "$CA_DIR/${WILDCARD_NAME}.csr.new" \
        -CA "$CA_DIR/${CA_NAME}.crt" \
        -CAkey "$CA_DIR/${CA_NAME}.key" \
        -CAcreateserial \
        -out "$CA_DIR/${WILDCARD_NAME}.crt.new" \
        -days 3650 -sha256 \
        -extfile "$CA_DIR/${WILDCARD_NAME}.ext" \
        >> "$LOG_FILE" 2>&1
    
    # Substitui os arquivos
    mv "$CA_DIR/${WILDCARD_NAME}.key.new" "$PRIVATE_DIR/${WILDCARD_NAME}.key"
    mv "$CA_DIR/${WILDCARD_NAME}.crt.new" "$CERTS_DIR/${WILDCARD_NAME}.crt"
    chmod 600 "$PRIVATE_DIR/${WILDCARD_NAME}.key"
    chmod 644 "$CERTS_DIR/${WILDCARD_NAME}.crt"
    
    # Gera PEM combinado
    cat "$PRIVATE_DIR/${WILDCARD_NAME}.key" "$CERTS_DIR/${WILDCARD_NAME}.crt" > "$PRIVATE_DIR/${WILDCARD_NAME}.pem"
    chmod 600 "$PRIVATE_DIR/${WILDCARD_NAME}.pem"
    
    log "Certificado renovado com sucesso. Novo certificado válido por mais 10 anos."
    
    # Reinicia o Samba
    systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1
    if systemctl is-active samba-ad-dc >/dev/null; then
        log "Samba reiniciado para aplicar o novo certificado."
    else
        error_exit "Falha ao reiniciar Samba."
    fi
else
    log "Certificado ainda válido por $days_left dias. Nenhuma ação necessária."
fi