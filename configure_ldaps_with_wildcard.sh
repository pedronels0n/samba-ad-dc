#!/bin/bash
# configurar_ldaps_com_ca.sh
# Após executar create_internal_ca.sh, este script configura o Samba e gera um arquivo .deb para distribuição da CA.

source "$(dirname "$0")/common.sh"

DOMAIN=$(hostname -d)
CA_DIR="/root/ca"

# Verifica se os arquivos existem
if [ ! -f "$CA_DIR/certs/ca-chain.crt.pem" ]; then
    error_exit "Cadeia de certificados não encontrada. Execute create_internal_ca.sh primeiro."
fi

# Faz backup do smb.conf
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)

# Atualiza as configurações TLS
sed -i '/^[[:space:]]*tls enabled/d' /etc/samba/smb.conf
sed -i '/^[[:space:]]*tls keyfile/d' /etc/samba/smb.conf
sed -i '/^[[:space:]]*tls certfile/d' /etc/samba/smb.conf
sed -i '/^[[:space:]]*tls cafile/d' /etc/samba/smb.conf

sed -i '/^\[global\]/a tls enabled = yes' /etc/samba/smb.conf
sed -i '/^\[global\]/a tls keyfile = '"$CA_DIR/private/wildcard.$DOMAIN.key.pem" /etc/samba/smb.conf
sed -i '/^\[global\]/a tls certfile = '"$CA_DIR/certs/wildcard.$DOMAIN.crt.pem" /etc/samba/smb.conf
sed -i '/^\[global\]/a tls cafile = '"$CA_DIR/certs/ca-chain.crt.pem" /etc/samba/smb.conf

log "Configurações TLS aplicadas no smb.conf."

# Reinicia o Samba
systemctl restart samba-ad-dc
log "Samba reiniciado."

# Cria um pacote .deb simples com o certificado da CA para distribuição
# (Isso é útil para clientes Debian/Ubuntu)
PKG_DIR="/tmp/samba-ca-deb"
mkdir -p "$PKG_DIR/DEBIAN" "$PKG_DIR/usr/local/share/ca-certificates"
cp "$CA_DIR/certs/ca.root.crt.pem" "$PKG_DIR/usr/local/share/ca-certificates/samba-ca.crt"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: samba-ca
Version: 1.0
Architecture: all
Maintainer: Admin <admin@$DOMAIN>
Description: CA raiz do Samba AD DC
 Instala o certificado da CA raiz no trust store do sistema.
EOF

cat > "$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
update-ca-certificates
EOF
chmod 755 "$PKG_DIR/DEBIAN/postinst"

dpkg-deb --build "$PKG_DIR" "/root/samba-ca.deb"
log "Pacote .deb criado: /root/samba-ca.deb"

info_box "LDAPS configurado com sucesso!\n\nPacote para clientes: /root/samba-ca.deb\nInstale nos clientes com: dpkg -i samba-ca.deb"