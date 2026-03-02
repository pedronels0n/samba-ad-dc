#!/bin/bash
# configure_ldaps_with_wildcard.sh - Usa o certificado wildcard para LDAPS

source "$(dirname "$0")/common.sh"

check_root
check_prereqs openssl cp chmod cat systemctl grep sed

# usa CA_DIR global ou valor padrão
CA_DIR="${CA_DIR:-/root/samba-ca}"
WILDCARD_KEY="$CA_DIR/wildcard.key"
WILDCARD_CERT="$CA_DIR/wildcard.crt"
CA_CERT="$CA_DIR/ca.crt"

for f in "$WILDCARD_KEY" "$WILDCARD_CERT" "$CA_CERT"; do
    [ -f "$f" ] || error_exit "Arquivo $f não encontrado. Execute setup_ca.sh primeiro."
done

# Diretório de destino no Samba
TLS_DIR="/var/lib/samba/private/tls"
mkdir -p "$TLS_DIR"

# Copia os certificados
cp "$WILDCARD_KEY" "$TLS_DIR/server.key"
cp "$WILDCARD_CERT" "$TLS_DIR/server.crt"
cp "$CA_CERT" "$TLS_DIR/ca.crt"

# Ajusta permissões
chmod 600 "$TLS_DIR/server.key"
chmod 644 "$TLS_DIR/server.crt" "$TLS_DIR/ca.crt"

# Concatena para PEM (se necessário)
cat "$TLS_DIR/server.key" "$TLS_DIR/server.crt" > "$TLS_DIR/server.pem"
chmod 600 "$TLS_DIR/server.pem"

# Configura o smb.conf para usar os novos certificados
SMB_CONF="/etc/samba/smb.conf"
BACKUP="${SMB_CONF}.wildcard.bak.$(date +%Y%m%d%H%M%S)"
cp "$SMB_CONF" "$BACKUP"

# Função para adicionar/substituir parâmetros
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
add_param "global" "tls cafile" "$TLS_DIR/ca.crt" "$SMB_CONF"

log "Configuração TLS atualizada com certificado wildcard."

# Reinicia o Samba
systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1
if systemctl is-active samba-ad-dc >/dev/null; then
    info_box "LDAPS agora usando certificado wildcard assinado pela CA interna.\nCA: $TLS_DIR/ca.crt"
else
    error_exit "Falha ao reiniciar samba-ad-dc."
fi