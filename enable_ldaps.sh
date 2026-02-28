#!/bin/bash
# enable_ldaps.sh - Configura LDAPS com certificado TLS

source "$(dirname "$0")/common.sh"

check_root

# Diretório para certificados
TLS_DIR="/var/lib/samba/private/tls"
mkdir -p "$TLS_DIR"

# Nome do servidor FQDN
FQDN=$(hostname -f)
DOMAIN=$(hostname -d)

# Define validade (em dias)
DAYS=3650

# Gera chave privada e certificado autoassinado
log "Gerando chave privada e certificado autoassinado para $FQDN..."
openssl req -x509 -nodes -days "$DAYS" -newkey rsa:2048 \
    -keyout "$TLS_DIR/server.key" \
    -out "$TLS_DIR/server.crt" \
    -subj "/CN=$FQDN/O=$DOMAIN/OU=Domain Controllers/C=BR" \
    >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    error_exit "Falha ao gerar certificado."
fi

# Ajusta permissões
chmod 600 "$TLS_DIR/server.key"
chmod 644 "$TLS_DIR/server.crt"

# Concatena em um arquivo PEM (para o Samba)
cat "$TLS_DIR/server.key" "$TLS_DIR/server.crt" > "$TLS_DIR/server.pem"
chmod 600 "$TLS_DIR/server.pem"

# Configura o Samba para usar o certificado
SMB_CONF="/etc/samba/smb.conf"
BACKUP="${SMB_CONF}.ldaps.bak.$(date +%Y%m%d%H%M%S)"
cp "$SMB_CONF" "$BACKUP"

# Adiciona parâmetros TLS na seção [global]
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
add_param "global" "tls keyfile" "$TLS_DIR/server.key" "$SMB_CONF"
add_param "global" "tls certfile" "$TLS_DIR/server.crt" "$SMB_CONF"
add_param "global" "tls cafile" "" "$SMB_CONF" # Vazio para autoassinado

log "Parâmetros TLS adicionados ao smb.conf."

# Reinicia o Samba
systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1
if systemctl is-active samba-ad-dc >/dev/null; then
    info_box "LDAPS configurado com certificado autoassinado.\nPorta 636 ativa. O certificado está em $TLS_DIR/server.crt"
else
    error_exit "Falha ao reiniciar samba-ad-dc."
fi