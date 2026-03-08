#!/bin/bash
# setup_ca.sh - Cria uma Autoridade Certificadora (CA) interna e gera um certificado wildcard para o domínio
# Uso: ./setup_ca.sh
# Autor: ...
# Descrição: Gera CA raiz e certificado wildcard válido por 10 anos para *.dominio

source "$(dirname "$0")/common.sh"

check_root
# garante que ferramentas necessárias estão presentes
check_prereqs openssl cp cat mkdir sed systemctl

# Define diretórios (CA_DIR padrão vem de common.sh, mas permitimos sobrescrever)
CA_DIR="${CA_DIR:-/root/samba-ca}"
CERTS_DIR="${CERTS_DIR:-/etc/ssl/certs}"  # ou /var/lib/samba/private/tls, mas vamos manter separado
PRIVATE_DIR="${PRIVATE_DIR:-/etc/ssl/private}"

mkdir -p "$CA_DIR" "$CERTS_DIR" "$PRIVATE_DIR"

# Obtém o domínio do hostname (ex: exemplo.local)
DOMAIN=$(hostname -d)
if [ -z "$DOMAIN" ]; then
    error_exit "Não foi possível determinar o domínio. Configure o hostname FQDN primeiro."
fi

# Nome do servidor FQDN
FQDN=$(hostname -f)

# Nome do arquivo sem extensão
CA_NAME="ca-${DOMAIN}"
WILDCARD_NAME="wildcard.${DOMAIN}"

# Validade em dias (10 anos)
DAYS=3650

# Informações do certificado
COUNTRY="BR"
STATE="Bahia"
LOCALITY="Lauro de Freitas"
ORGANIZATION="PMLF"
ORG_UNIT="TI"
COMMON_NAME="CA $DOMAIN"
EMAIL="admin@$DOMAIN"

# Gera a chave privada da CA (protegida com senha? Vamos usar sem senha para facilitar, mas em produção recomenda-se senha)
log "Gerando chave privada da CA..."
openssl genrsa -out "$CA_DIR/${CA_NAME}.key" 4096 >> "$LOG_FILE" 2>&1
chmod 600 "$CA_DIR/${CA_NAME}.key"

# Gera o certificado da CA (autoassinado)
log "Gerando certificado da CA (válido por $DAYS dias)..."
openssl req -x509 -new -nodes -key "$CA_DIR/${CA_NAME}.key" \
    -sha256 -days "$DAYS" \
    -out "$CA_DIR/${CA_NAME}.crt" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$COMMON_NAME/emailAddress=$EMAIL" \
    >> "$LOG_FILE" 2>&1

# Copia o certificado da CA para local público (para distribuição)
cp "$CA_DIR/${CA_NAME}.crt" "$CERTS_DIR/"
log "Certificado da CA disponível em $CERTS_DIR/${CA_NAME}.crt"

# Gera a chave privada do certificado wildcard
log "Gerando chave privada do certificado wildcard..."
openssl genrsa -out "$CA_DIR/${WILDCARD_NAME}.key" 2048 >> "$LOG_FILE" 2>&1
chmod 600 "$CA_DIR/${WILDCARD_NAME}.key"

# Cria uma requisição de assinatura de certificado (CSR) para o wildcard
log "Criando CSR para $WILDCARD_NAME..."
openssl req -new -key "$CA_DIR/${WILDCARD_NAME}.key" \
    -out "$CA_DIR/${WILDCARD_NAME}.csr" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=*.$DOMAIN/emailAddress=$EMAIL" \
    >> "$LOG_FILE" 2>&1

# Prepara arquivo de extensões x509 v3 para incluir SAN (Subject Alternative Name)
# O Samba exige que o nome do servidor (FQDN) esteja no SAN ou CN. Vamos colocar CN=*.$DOMAIN e SAN com DNS:*.$DOMAIN e DNS:$FQDN
cat > "$CA_DIR/${WILDCARD_NAME}.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

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
    -days "$DAYS" -sha256 \
    -extfile "$CA_DIR/${WILDCARD_NAME}.ext" \
    >> "$LOG_FILE" 2>&1

# Copia o certificado wildcard e a chave para o diretório do Samba (ou /etc/ssl)
# Vamos copiar para /etc/ssl/certs e /etc/ssl/private
cp "$CA_DIR/${WILDCARD_NAME}.crt" "$CERTS_DIR/"
cp "$CA_DIR/${WILDCARD_NAME}.key" "$PRIVATE_DIR/"
chmod 644 "$CERTS_DIR/${WILDCARD_NAME}.crt"
chmod 600 "$PRIVATE_DIR/${WILDCARD_NAME}.key"

log "Certificado wildcard gerado: $CERTS_DIR/${WILDCARD_NAME}.crt"
log "Chave privada: $PRIVATE_DIR/${WILDCARD_NAME}.key"

# Opcional: criar um arquivo PEM (chave + certificado) para uso no Samba
cat "$PRIVATE_DIR/${WILDCARD_NAME}.key" "$CERTS_DIR/${WILDCARD_NAME}.crt" > "$CA_DIR/${WILDCARD_NAME}.pem"
cp "$CA_DIR/${WILDCARD_NAME}.pem" "$PRIVATE_DIR/"
chmod 600 "$PRIVATE_DIR/${WILDCARD_NAME}.pem"

log "Arquivo PEM combinado criado: $PRIVATE_DIR/${WILDCARD_NAME}.pem"

# Agora precisamos configurar o Samba para usar este certificado
# Se o smb.conf já existir, vamos ajustar os parâmetros tls.
SMB_CONF="/etc/samba/smb.conf"
if [ -f "$SMB_CONF" ]; then
    # Faz backup
    cp "$SMB_CONF" "$SMB_CONF.bak.ca.$(date +%Y%m%d%H%M%S)"
    
    # Função para adicionar ou substituir parâmetros (já definida em common.sh ou repetimos)
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
    
    log "Configuração TLS no smb.conf atualizada para usar o certificado wildcard e a CA."
else
    log "Arquivo smb.conf não encontrado. Você precisará configurar manualmente após provisionar o domínio."
fi

# Reinicia o Samba para aplicar as mudanças (se estiver em execução)
if systemctl is-active samba-ad-dc >/dev/null 2>&1; then
    systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1
    log "Samba reiniciado para aplicar novo certificado."
fi

info_box "CA e certificado wildcard criados com sucesso!\n\nCA: $CERTS_DIR/${CA_NAME}.crt\nCertificado wildcard: $CERTS_DIR/${WILDCARD_NAME}.crt\nChave: $PRIVATE_DIR/${WILDCARD_NAME}.key\n\nIMPORTANTE: Distribua o certificado da CA para todos os clientes da rede para que confiem no certificado."