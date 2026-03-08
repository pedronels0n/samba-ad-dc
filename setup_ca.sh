#!/bin/bash
# setup_ca.sh - Cria uma Autoridade Certificadora (CA) interna e gera um certificado wildcard para o domínio
# Uso: ./setup_ca.sh
# Autor: ...
# Descrição: Gera CA raiz e certificado wildcard válido por 10 anos para *.dominio

source "$(dirname "$0")/common.sh"

check_root
check_prereqs openssl cp cat mkdir sed systemctl

# Define diretórios
CA_DIR="${CA_DIR:-/root/samba-ca}"
CERTS_DIR="${CERTS_DIR:-/etc/ssl/certs}"
PRIVATE_DIR="${PRIVATE_DIR:-/etc/ssl/private}"
mkdir -p "$CA_DIR" "$CERTS_DIR" "$PRIVATE_DIR"
chmod 700 "$PRIVATE_DIR"

# Obtém o domínio do hostname
DOMAIN=$(hostname -d)
if [ -z "$DOMAIN" ]; then
    error_exit "Não foi possível determinar o domínio. Configure o hostname FQDN primeiro."
fi

FQDN=$(hostname -f)
CA_NAME="ca-${DOMAIN}"
WILDCARD_NAME="wildcard.${DOMAIN}"
DAYS_CA=7300      # 20 anos para CA raiz
DAYS_CERT=3650    # 10 anos para o certificado (ou 365 para 1 ano)

# Informações do certificado (ajuste conforme necessário)
COUNTRY="BR"
STATE="Bahia"
LOCALITY="Lauro de Freitas"
ORGANIZATION="PMLF"
ORG_UNIT="TI"
EMAIL="admin@$DOMAIN"

# Verifica se já existe uma CA (para não sobrescrever sem aviso)
if [ -f "$CA_DIR/${CA_NAME}.key" ] || [ -f "$CERTS_DIR/${CA_NAME}.crt" ]; then
    log "Uma CA existente foi encontrada."
    read -p "Deseja sobrescrever? (s/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        info_box "Operação cancelada. Mantendo CA existente."
        exit 0
    fi
    # Faz backup
    BACKUP_CA_DIR="$CA_DIR/backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$BACKUP_CA_DIR"
    cp "$CA_DIR/${CA_NAME}".* "$BACKUP_CA_DIR/" 2>/dev/null
    cp "$CERTS_DIR/${CA_NAME}.crt" "$BACKUP_CA_DIR/" 2>/dev/null
    log "Backup da CA antiga em $BACKUP_CA_DIR"
fi

# Gera a chave privada da CA (protegida com permissões)
log "Gerando chave privada da CA (4096 bits)..."
openssl genrsa -out "$CA_DIR/${CA_NAME}.key" 4096 >> "$LOG_FILE" 2>&1
chmod 600 "$CA_DIR/${CA_NAME}.key"

# Gera o certificado da CA (autoassinado)
log "Gerando certificado da CA (válido por $DAYS_CA dias)..."
openssl req -x509 -new -nodes -key "$CA_DIR/${CA_NAME}.key" \
    -sha256 -days "$DAYS_CA" \
    -out "$CA_DIR/${CA_NAME}.crt" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$DOMAIN CA/emailAddress=$EMAIL" \
    >> "$LOG_FILE" 2>&1

# Copia o certificado da CA para local público
cp "$CA_DIR/${CA_NAME}.crt" "$CERTS_DIR/"
chmod 644 "$CERTS_DIR/${CA_NAME}.crt"
log "Certificado da CA disponível em $CERTS_DIR/${CA_NAME}.crt"

# Verifica se já existe um wildcard (para não sobrescrever sem aviso)
if [ -f "$CA_DIR/${WILDCARD_NAME}.key" ] || [ -f "$CERTS_DIR/${WILDCARD_NAME}.crt" ]; then
    log "Um certificado wildcard existente foi encontrado."
    read -p "Deseja sobrescrever? (s/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        log "Mantendo certificado wildcard existente."
    else
        # Backup opcional (pode pular)
        :
    fi
fi

# Gera a chave privada do certificado wildcard
log "Gerando chave privada do certificado wildcard (2048 bits)..."
openssl genrsa -out "$CA_DIR/${WILDCARD_NAME}.key" 2048 >> "$LOG_FILE" 2>&1
chmod 600 "$CA_DIR/${WILDCARD_NAME}.key"

# Cria uma requisição de assinatura (CSR)
log "Criando CSR para *.$DOMAIN..."
openssl req -new -key "$CA_DIR/${WILDCARD_NAME}.key" \
    -out "$CA_DIR/${WILDCARD_NAME}.csr" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=*.$DOMAIN/emailAddress=$EMAIL" \
    >> "$LOG_FILE" 2>&1

# Arquivo de extensões x509 v3 com SAN
cat > "$CA_DIR/${WILDCARD_NAME}.ext" <<EOF
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = *.$DOMAIN
DNS.2 = $FQDN
EOF

# Assina o certificado com a CA
log "Assinando o certificado wildcard com a CA..."
openssl x509 -req -in "$CA_DIR/${WILDCARD_NAME}.csr" \
    -CA "$CA_DIR/${CA_NAME}.crt" \
    -CAkey "$CA_DIR/${CA_NAME}.key" \
    -CAcreateserial \
    -out "$CA_DIR/${WILDCARD_NAME}.crt" \
    -days "$DAYS_CERT" -sha256 \
    -extfile "$CA_DIR/${WILDCARD_NAME}.ext" \
    >> "$LOG_FILE" 2>&1

# Copia o certificado e a chave para os diretórios finais
cp "$CA_DIR/${WILDCARD_NAME}.crt" "$CERTS_DIR/"
cp "$CA_DIR/${WILDCARD_NAME}.key" "$PRIVATE_DIR/"
chmod 644 "$CERTS_DIR/${WILDCARD_NAME}.crt"
chmod 600 "$PRIVATE_DIR/${WILDCARD_NAME}.key"

log "Certificado wildcard: $CERTS_DIR/${WILDCARD_NAME}.crt"
log "Chave privada: $PRIVATE_DIR/${WILDCARD_NAME}.key"

# Cria arquivo PEM combinado (opcional)
cat "$PRIVATE_DIR/${WILDCARD_NAME}.key" "$CERTS_DIR/${WILDCARD_NAME}.crt" > "$CA_DIR/${WILDCARD_NAME}.pem"
chmod 600 "$CA_DIR/${WILDCARD_NAME}.pem"
log "Arquivo PEM combinado: $CA_DIR/${WILDCARD_NAME}.pem"

# Cria cadeia da CA (apenas a raiz, já que não temos intermediária)
cp "$CERTS_DIR/${CA_NAME}.crt" "$CA_DIR/ca-chain.crt"
log "Cadeia da CA: $CA_DIR/ca-chain.crt"

# Configura o Samba para usar o certificado
SMB_CONF="/etc/samba/smb.conf"
if [ -f "$SMB_CONF" ]; then
    cp "$SMB_CONF" "$SMB_CONF.bak.ca.$(date +%Y%m%d%H%M%S)"
    
    # Função add_param (se não existir no common.sh)
    add_param() {
        local section="$1"
        local param="$2"
        local value="$3"
        local file="$4"
        if ! grep -q "^\[$section\]" "$file"; then
            echo "[$section]" >> "$file"
        fi
        sed -i "/^\[$section\]/,/^\[/ { /^$param[[:space:]]*=/ d }" "$file"
        sed -i "/^\[$section\]/a $param = $value" "$file"
    }
    
    add_param "global" "tls enabled" "yes" "$SMB_CONF"
    add_param "global" "tls keyfile" "$PRIVATE_DIR/${WILDCARD_NAME}.key" "$SMB_CONF"
    add_param "global" "tls certfile" "$CERTS_DIR/${WILDCARD_NAME}.crt" "$SMB_CONF"
    add_param "global" "tls cafile" "$CERTS_DIR/${CA_NAME}.crt" "$SMB_CONF"
    
    log "Configuração TLS no smb.conf atualizada."
    
    # Reinicia o Samba se ativo
    if systemctl is-active samba-ad-dc >/dev/null 2>&1; then
        systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1
        log "Samba reiniciado."
    fi
else
    log "Arquivo smb.conf não encontrado. Configure manualmente os parâmetros TLS."
fi

# Resumo final
echo
log "=== RESUMO ==="
echo "CA raiz:        $CERTS_DIR/${CA_NAME}.crt"
echo "Chave da CA:    $CA_DIR/${CA_NAME}.key (mantido em local seguro)"
echo "Wildcard CRT:   $CERTS_DIR/${WILDCARD_NAME}.crt"
echo "Wildcard KEY:   $PRIVATE_DIR/${WILDCARD_NAME}.key"
echo "Wildcard PEM:   $CA_DIR/${WILDCARD_NAME}.pem"
echo "Cadeia CA:      $CA_DIR/ca-chain.crt"
echo
echo "Para clientes confiarem, distribua: $CERTS_DIR/${CA_NAME}.crt"
echo "Em sistemas Linux:"
echo "  sudo cp $CERTS_DIR/${CA_NAME}.crt /usr/local/share/ca-certificates/"
echo "  sudo update-ca-certificates"
echo "Em Windows: importe como Autoridade de Certificação Raiz Confiável."
sleep 10

info_box "CA e certificado wildcard criados com sucesso!\n\nCA: $CERTS_DIR/${CA_NAME}.crt\nWildcard: $CERTS_DIR/${WILDCARD_NAME}.crt"