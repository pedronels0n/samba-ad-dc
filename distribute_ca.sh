#!/bin/bash
# distribute_ca.sh - Distribui a CA raiz para todos os clientes via Samba

source "$(dirname "$0")/common.sh"

check_root

CA_FILE="/root/ca/certs/ca.root.crt.pem"
PUBLIC_DIR="/var/lib/samba/public"
SMB_CONF="/etc/samba/smb.conf"

# Verifica se o certificado existe
if [ ! -f "$CA_FILE" ]; then
    error_exit "Certificado da CA não encontrado em $CA_FILE"
fi

# Cria diretório público se não existir
mkdir -p "$PUBLIC_DIR"
log "Diretório $PUBLIC_DIR criado/verificado"

# Copia a CA para o diretório público do Samba
cp "$CA_FILE" "$PUBLIC_DIR/ca-root.crt"
chmod 644 "$PUBLIC_DIR/ca-root.crt"
log "Certificado copiado para $PUBLIC_DIR/ca-root.crt"

# Verifica se o compartilhamento [public] já existe no smb.conf
if ! grep -q "^\[public\]" "$SMB_CONF"; then
    log "Adicionando compartilhamento [public] ao smb.conf..."
    
    # Faz backup do smb.conf
    cp "$SMB_CONF" "$SMB_CONF.bak.$(date +%Y%m%d%H%M%S)"
    
    # Adiciona o compartilhamento
    cat >> "$SMB_CONF" <<EOF

[public]
    comment = Certificados e Arquivos Públicos
    path = $PUBLIC_DIR
    read only = yes
    browseable = yes
    guest ok = yes
    force user = nobody
    force group = nogroup
    create mask = 0644
    directory mask = 0755
EOF
    log "Compartilhamento [public] adicionado ao smb.conf"
    
    # Reinicia o Samba para aplicar as mudanças
    log "Reiniciando samba-ad-dc..."
    systemctl restart samba-ad-dc
    sleep 3
    
    if systemctl is-active samba-ad-dc; then
        log "Samba reiniciado com sucesso!"
    else
        error_exit "Falha ao reiniciar samba-ad-dc"
    fi
else
    log "Compartilhamento [public] já existe no smb.conf"
fi

# Testa se o compartilhamento está acessível
log "Testando compartilhamento..."
if smbclient -L localhost -N 2>/dev/null | grep -q "public"; then
    log "✓ Compartilhamento [public] está disponível"
else
    log "⚠️  Compartilhamento [public] configurado, mas pode precisar de alguns segundos para aparecer"
fi

# Mostra as informações
HOSTNAME=$(hostname -f)
echo
log "=== CA RAIZ DISPONÍVEL ==="
echo "Caminho Linux:  $PUBLIC_DIR/ca-root.crt"
echo "Caminho Windows: \\\\$HOSTNAME\\public\\ca-root.crt"
echo
echo "=== INSTRUÇÕES PARA CLIENTES ==="
echo
echo "📌 LINUX:"
echo "  sudo cp /mnt/public/ca-root.crt /usr/local/share/ca-certificates/samba-ca.crt"
echo "  sudo update-ca-certificates"
echo "  # Para montar o compartilhamento:"
echo "  sudo mount -t cifs //$HOSTNAME/public /mnt/public -o guest"
echo
echo "📌 WINDOWS (PowerShell como Administrador):"
echo "  certutil -addstore -f Root \\\\$HOSTNAME\\public\\ca-root.crt"
echo
echo "📌 Para testar a conexão LDAPS após instalar:"
echo "  Linux:  ldapsearch -H ldaps://$HOSTNAME -x -b \"dc=$(hostname -d | sed 's/\./,dc=/g')\""
echo "  Windows: LDP.exe ou PowerShell com System.DirectoryServices"
echo "=========================================="

sleep 30

info_box "✅ CA raiz distribuída com sucesso!\n\nArquivo: \\\\$HOSTNAME\\public\\ca-root.crt\n\nInstruções detalhadas no console."