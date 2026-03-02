#!/bin/bash
# harden_samba.sh - Aplica configurações de segurança no Samba DC

source "$(dirname "$0")/common.sh"

check_root

# Arquivo smb.conf
SMB_CONF="/etc/samba/smb.conf"
BACKUP="${SMB_CONF}.hardening.bak.$(date +%Y%m%d%H%M%S)"

# Faz backup
cp "$SMB_CONF" "$BACKUP"
log "Backup de $SMB_CONF criado em $BACKUP"

# Função para adicionar ou substituir parâmetros em uma seção
add_param() {
    local section="$1"
    local param="$2"
    local value="$3"
    local file="$4"
    
    # Verifica se a seção existe
    if ! grep -q "^\[$section\]" "$file"; then
        echo "[$section]" >> "$file"
    fi
    
    # Remove linha existente (se houver) e adiciona nova
    sed -i "/^\[$section\]/,/^\[/ { /^$param[[:space:]]*=/ d }" "$file"
    sed -i "/^\[$section\]/a $param = $value" "$file"
}

log "Aplicando configurações de hardening..."

# Seção [global]
add_param "global" "restrict anonymous" "2" "$SMB_CONF"
add_param "global" "disable netbios" "yes" "$SMB_CONF"
add_param "global" "smb ports" "445" "$SMB_CONF"  # Desabilita porta 139 (legada)
add_param "global" "load printers" "no" "$SMB_CONF"
add_param "global" "printing" "bsd" "$SMB_CONF"
add_param "global" "printcap name" "/dev/null" "$SMB_CONF"
add_param "global" "disable spoolss" "yes" "$SMB_CONF"
add_param "global" "ntlm auth" "ntlmv2-only" "$SMB_CONF"
add_param "global" "rpc server dynamic port range" "50000-55000" "$SMB_CONF"
add_param "global" "server signing" "mandatory" "$SMB_CONF"
add_param "global" "client signing" "required" "$SMB_CONF"
add_param "global" "smb encrypt" "auto" "$SMB_CONF"
add_param "global" "server multi channel support" "no" "$SMB_CONF" # Desabilita WPAD? Não diretamente, mas WPAD é DNS.

# Auditoria (full_audit)
add_param "global" "vfs objects" "full_audit" "$SMB_CONF"
add_param "global" "full_audit:prefix" "%u|%I|%m|%S" "$SMB_CONF"
add_param "global" "full_audit:success" "mkdir rmdir open create unlink chmod chown write rename" "$SMB_CONF"
add_param "global" "full_audit:failure" "open" "$SMB_CONF"
add_param "global" "full_audit:facility" "local7" "$SMB_CONF"
add_param "global" "full_audit:priority" "notice" "$SMB_CONF"

# Log de alterações no sysvol (via logging = ...?) - O full_audit já cobre.
# Para auditoria de GPO (LDAP), usaremos samba-tool later.

# Configurações adicionais via samba-tool
log "Desabilitando listagem anônima de usuários..."
samba-tool domain passwordsettings set --anonymous-export=no >> "$LOG_FILE" 2>&1

log "Habilitando apenas AES256 e AES128 para Kerberos..."
samba-tool domain settings kerberos aes enable --all >> "$LOG_FILE" 2>&1
samba-tool domain settings kerberos des disable >> "$LOG_FILE" 2>&1
samba-tool domain settings kerberos rc4 disable >> "$LOG_FILE" 2>&1

log "Desabilitando WPAD e ISATAP via DNS (removendo registros)..."
# Remove registros WPAD e ISATAP se existirem
HOST=$(hostname -f)
DOMAIN=$(hostname -d)
samba-tool dns delete "$HOST" "$DOMAIN" WPAD A @ -U Administrator >> "$LOG_FILE" 2>&1 || true
samba-tool dns delete "$HOST" "$DOMAIN" ISATAP A @ -U Administrator >> "$LOG_FILE" 2>&1 || true

# Auditoria de login e GPO (via samba-tool ou ajustes no smb.conf?)
# Para auditoria de login, pode-se usar o parâmetro "log level = 3" e monitorar.
# Vamos configurar nível de log mais detalhado e específico.
add_param "global" "log level" "3 auth:5 ldap:5" "$SMB_CONF"

# Habilita auditoria de alterações em GPO (via LDAP) - O full_audit já registra operações de arquivo no sysvol.
# No entanto, para alterações no LDAP, o Samba já loga dependendo do nível.

log "Configurações de hardening aplicadas no smb.conf."

# Reinicia o Samba para aplicar as mudanças
systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1
if systemctl is-active samba-ad-dc >/dev/null; then
    info_box "Hardening aplicado e serviço reiniciado com sucesso."
else
    error_exit "Falha ao reiniciar samba-ad-dc. Verifique o log."
fi