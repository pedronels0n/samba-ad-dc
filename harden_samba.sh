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
add_param "global" "smb ports" "445" "$SMB_CONF"  # Desabilita porta 139 (legado)
add_param "global" "load printers" "no" "$SMB_CONF"
add_param "global" "printing" "bsd" "$SMB_CONF"
add_param "global" "printcap name" "/dev/null" "$SMB_CONF"
add_param "global" "disable spoolss" "yes" "$SMB_CONF"
add_param "global" "ntlm auth" "mschapv2-and-ntlmv2-only" "$SMB_CONF"
add_param "global" "rpc server dynamic port range" "50000-55000" "$SMB_CONF"
add_param "global" "server signing" "mandatory" "$SMB_CONF"
add_param "global" "client signing" "mandatory" "$SMB_CONF"
add_param "global" "smb encrypt" "auto" "$SMB_CONF"
add_param "global" "server multi channel support" "no" "$SMB_CONF" # Desabilita WPAD? Não diretamente, mas WPAD é DNS.

# Auditoria (full_audit)
add_param "global" "vfs objects" "full_audit" "$SMB_CONF"
add_param "global" "full_audit:prefix" "IP=%I|USER=%u|MACHINE=%m|VOLUME=%S" "$SMB_CONF"
add_param "global" "full_audit:success" "pwrite renameat mkdirat unlinkat fchmod fchown openat" "$SMB_CONF"
add_param "global" "full_audit:failure" "none" "$SMB_CONF"
add_param "global" "full_audit:facility" "local7" "$SMB_CONF"
add_param "global" "full_audit:priority" "NOTICE" "$SMB_CONF"

# Log de alterações no sysvol (via logging = ...?) - O full_audit já cobre.
# Para auditoria de GPO (LDAP), usaremos samba-tool later.

# Configurações adicionais via samba-tool
log "Desabilitando listagem anônima de usuários..."
samba-tool domain passwordsettings set --anonymous-export=no

log "Habilitando apenas AES256 e AES128 para Kerberos..."
samba-tool -U Administrator domain settings kerberos aes enable --all 
samba-tool -U Administrator domain settings kerberos des disable
samba-tool -U Administrator domain settings kerberos rc4 disable 

log "Desabilitando WPAD e ISATAP via DNS (removendo registros)..."
# Remove registros WPAD e ISATAP se existirem
HOST=$(hostname -f)
DOMAIN=$(hostname -d)
samba-tool dns delete "$HOST" "$DOMAIN" WPAD A @ -U Administrator
samba-tool dns delete "$HOST" "$DOMAIN" ISATAP A @ -U Administrator

# Auditoria de login e GPO (via samba-tool ou ajustes no smb.conf?)
# Para auditoria de login, pode-se usar o parâmetro "log level = 3" e monitorar.
# Vamos configurar nível de log mais detalhado e específico.
add_param "global" "log level" "1 auth_audit:3 auth_json_audit:3 dsdb_audit:3 dsdb_json_audit:3 winbind:2" "$SMB_CONF"
add_param "global" "logging" "file" "$SMB_CONF"
add_param "global" "max log size" "10000" "$SMB_CONF"

# Habilita auditoria de alterações em GPO (via LDAP) - O full_audit já registra operações de arquivo no sysvol.
# No entanto, para alterações no LDAP, o Samba já loga dependendo do nível.

log "Configurações de hardening aplicadas no smb.conf."

# Reinicia o Samba para aplicar as mudanças
systemctl restart samba-ad-dc
if systemctl is-active samba-ad-dc >/dev/null; then
    info_box "Hardening aplicado e serviço reiniciado com sucesso."
else
    error_exit "Falha ao reiniciar samba-ad-dc. Verifique o log."
fi

# --- Adiciona vfs full_audit às seções [sysvol] e [netlogon] com as configurações do manual
insert_share_audit() {
    local file="$1"
    local section="$2"

    if ! grep -q "^\[$section\]" "$file"; then
        echo "[$section]" >> "$file"
    fi

    # Remove linhas antigas relacionadas a vfs/full_audit
    sed -i "/^\[$section\]/,/^\[/ { /vfs objects/d; /full_audit:/d; /full_audit\:prefix/d }" "$file"

    # Insere as linhas após o header da seção
    sed -i "/^\[$section\]/a vfs objects = dfs_samba4 acl_xattr full_audit\nfull_audit:failure = none\nfull_audit:success = pwrite renameat mkdirat unlinkat fchmod fchown openat\nfull_audit:prefix = IP=%I|USER=%u|MACHINE=%m|VOLUME=%S\nfull_audit:facility = local7\nfull_audit:priority = NOTICE" "$file"
}

insert_share_audit "$SMB_CONF" "sysvol"
insert_share_audit "$SMB_CONF" "netlogon"

# --- Configura rsyslog e logrotate para auditoria Samba
RSYSLOG_FILE="/etc/rsyslog.d/00-samba-audit.conf"
LOGROTATE_FILE="/etc/logrotate.d/samba-audit"
cat > "$RSYSLOG_FILE" <<EOF
local7.* /var/log/samba/audit.log
& stop
EOF

cat > "$LOGROTATE_FILE" <<'EOF'
/var/log/samba/audit.log {
    weekly
    missingok
    rotate 8
    compress
    delaycompress
    notifempty
    postrotate
        /usr/bin/systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF

log "Arquivos de rsyslog e logrotate criados: $RSYSLOG_FILE, $LOGROTATE_FILE"

# Reinicia rsyslog para aplicar a configuração de log
systemctl restart rsyslog || log "Aviso: falha ao reiniciar rsyslog"

# --- Hardening Kerberos: ajusta default_etypes conforme manual
KRB5_CONF="/etc/krb5.conf"
if [ -f "$KRB5_CONF" ]; then
    cp "$KRB5_CONF" "${KRB5_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    if grep -q "^default_etypes" "$KRB5_CONF"; then
        sed -i "s|^default_etypes.*|default_etypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96|" "$KRB5_CONF"
    else
        # Insere dentro da seção [libdefaults]
        if grep -q "^\[libdefaults\]" "$KRB5_CONF"; then
            sed -i "/^\[libdefaults\]/a default_etypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96" "$KRB5_CONF"
        else
            echo -e "[libdefaults]\ndefault_etypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96" >> "$KRB5_CONF"
        fi
    fi
    log "Arquivo $KRB5_CONF atualizado com default_etypes recomendados."
else
    log "Arquivo $KRB5_CONF não encontrado; pulando ajuste de krb5.conf"
fi