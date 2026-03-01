#!/bin/bash
# finalize_samba_security.sh - Restaura auditoria e aplica criptografia obrigatória

source "$(dirname "$0")/common.sh"

check_root

SMB_CONF="/etc/samba/smb.conf"
BACKUP="${SMB_CONF}.final.bak.$(date +%Y%m%d%H%M%S)"
cp "$SMB_CONF" "$BACKUP"
log "Backup criado: $BACKUP"

# Restaura full_audit nas seções [sysvol] e [netlogon]
log "Restaurando full_audit em [sysvol] e [netlogon]..."
sed -i '/^\[sysvol\]/,/^\[/ s/vfs objects = dfs_samba4 acl_xattr/vfs objects = dfs_samba4 acl_xattr full_audit/' "$SMB_CONF"
sed -i '/^\[netlogon\]/,/^\[/ s/vfs objects = dfs_samba4 acl_xattr/vfs objects = dfs_samba4 acl_xattr full_audit/' "$SMB_CONF"

# Adiciona smb encrypt = mandatory (se não existir)
if grep -q "^[[:space:]]*smb encrypt" "$SMB_CONF"; then
    sed -i 's/^[[:space:]]*smb encrypt.*/smb encrypt = mandatory/' "$SMB_CONF"
else
    sed -i '/^\[global\]/a smb encrypt = mandatory' "$SMB_CONF"
fi

log "Reiniciando Samba para aplicar as alterações..."
systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1
if systemctl is-active samba-ad-dc >/dev/null; then
    info_box "Configurações finais aplicadas:\n" \
             "- full_audit restaurado em [sysvol] e [netlogon]\n" \
             "- smb encrypt = mandatory\n" \
             "Serviço reiniciado com sucesso."
else
    error_exit "Falha ao reiniciar Samba. Verifique o log."
fi