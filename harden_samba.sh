#!/bin/bash
# harden_samba.sh - Aplica configurações de segurança no Samba DC

source "$(dirname "$0")/common.sh"

check_root

# Credenciais do administrador
ADMIN_USER="${ADMIN_USER:-Administrator}"
ADMIN_PASS="${ADMIN_PASS:-}"

# Se a senha não foi fornecida via ambiente, solicita via dialog
if [ -z "$ADMIN_PASS" ]; then
    exec 3>&1
    ADMIN_PASS=$(dialog --stdout --title "Senha do Administrador" \
        --passwordbox "Digite a senha do usuário $ADMIN_USER:" 8 50)
    exec 3>&-
    
    if [ -z "$ADMIN_PASS" ]; then
        error_exit "Senha não informada."
    fi
fi

# Função para executar samba-tool com autenticação
samba_tool_auth() {
    samba-tool "$@" -U "$ADMIN_USER" --password="$ADMIN_PASS"
}

# Testa autenticação
log "Testando autenticação..."
if ! samba_tool_auth domain info 127.0.0.1 >/dev/null 2>&1; then
    error_exit "Falha na autenticação. Verifique a senha do administrador."
fi
log "Autenticação bem-sucedida!"

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
add_param "global" "server multi channel support" "no" "$SMB_CONF"
add_param "global" "log level" "1 auth_audit:3 auth_json_audit:3 dsdb_audit:3 dsdb_json_audit:3 winbind:2" "$SMB_CONF"
add_param "global" "logging" "file" "$SMB_CONF"
add_param "global" "max log size" "10000" "$SMB_CONF"

# Auditoria (full_audit) - Configuração global
add_param "global" "vfs objects" "full_audit" "$SMB_CONF"
add_param "global" "full_audit:prefix" "IP=%I|USER=%u|MACHINE=%m|VOLUME=%S" "$SMB_CONF"
add_param "global" "full_audit:success" "pwrite renameat mkdirat unlinkat fchmod fchown openat" "$SMB_CONF"
add_param "global" "full_audit:failure" "none" "$SMB_CONF"
add_param "global" "full_audit:facility" "local7" "$SMB_CONF"
add_param "global" "full_audit:priority" "NOTICE" "$SMB_CONF"

log "Configurações de hardening aplicadas no smb.conf."

# --- Configurações via samba-tool ---
log "Aplicando políticas de segurança via samba-tool..."

# Configurar políticas de senha
log "Configurando políticas de senha..."
samba_tool_auth domain passwordsettings set \
    --complexity=on \
    --history-length=24 \
    --min-pwd-length=14 \
    --min-pwd-age=1 \
    --max-pwd-age=90 \
    --account-lockout-threshold=5 \
    --account-lockout-duration=30 \
    --reset-account-lockout-after=30

# Habilitar apenas AES para Kerberos (via smb.conf)
log "Configurando Kerberos para usar apenas AES..."
add_param "global" "kerberos method" "system keytab" "$SMB_CONF"
add_param "global" "dedicated keytab file" "/etc/krb5.keytab" "$SMB_CONF"
add_param "global" "kdc default service ticket lifetime" "1h" "$SMB_CONF"
add_param "global" "kdc user ticket lifetime" "10h" "$SMB_CONF"

# Desabilitar algoritmos fracos no krb5.conf
KRB5_CONF="/etc/krb5.conf"
if [ -f "$KRB5_CONF" ]; then
    cp "$KRB5_CONF" "${KRB5_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    
    # Configurar para usar apenas AES
    if grep -q "^\[libdefaults\]" "$KRB5_CONF"; then
        # Remove configurações existentes
        sed -i "/^\[libdefaults\]/,/^\[/ { /^[[:space:]]*default_tgs_enctypes/d }" "$KRB5_CONF"
        sed -i "/^\[libdefaults\]/,/^\[/ { /^[[:space:]]*default_tkt_enctypes/d }" "$KRB5_CONF"
        sed -i "/^\[libdefaults\]/,/^\[/ { /^[[:space:]]*permitted_enctypes/d }" "$KRB5_CONF"
        sed -i "/^\[libdefaults\]/,/^\[/ { /^[[:space:]]*allow_weak_crypto/d }" "$KRB5_CONF"
        
        # Adiciona configurações AES
        sed -i "/^\[libdefaults\]/a default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96" "$KRB5_CONF"
        sed -i "/^\[libdefaults\]/a default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96" "$KRB5_CONF"
        sed -i "/^\[libdefaults\]/a permitted_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96" "$KRB5_CONF"
        sed -i "/^\[libdefaults\]/a allow_weak_crypto = false" "$KRB5_CONF"
    else
        # Adiciona seção [libdefaults] ao final do arquivo
        cat >> "$KRB5_CONF" <<EOF

[libdefaults]
        default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
        default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
        permitted_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
        allow_weak_crypto = false
EOF
    fi
    
    log "Arquivo $KRB5_CONF atualizado para usar apenas AES."
fi

# Verificar suporte a LDAPS
log "Verificando configuração LDAPS..."
if ! grep -q "tls enabled" "$SMB_CONF"; then
    log "LDAPS não configurado. Execute enable_ldaps.sh para ativar."
fi

log "Desabilitando WPAD e ISATAP via DNS (removendo registros)..."
# Remove registros WPAD e ISATAP se existirem
HOST=$(hostname -f)
DOMAIN=$(hostname -d)

# Tenta remover WPAD
if samba_tool_auth dns query "$HOST" "$DOMAIN" WPAD A >/dev/null 2>&1; then
    samba_tool_auth dns delete "$HOST" "$DOMAIN" WPAD A "$HOST" && log "Registro WPAD removido."
else
    log "Registro WPAD não encontrado."
fi

# Tenta remover ISATAP
if samba_tool_auth dns query "$HOST" "$DOMAIN" ISATAP A >/dev/null 2>&1; then
    samba_tool_auth dns delete "$HOST" "$DOMAIN" ISATAP A "$HOST" && log "Registro ISATAP removido."
else
    log "Registro ISATAP não encontrado."
fi

# --- Adiciona vfs full_audit às seções [sysvol] e [netlogon] ---
insert_share_audit() {
    local file="$1"
    local section="$2"

    if ! grep -q "^\[$section\]" "$file"; then
        echo "[$section]" >> "$file"
    fi

    # Remove linhas antigas relacionadas a vfs/full_audit
    sed -i "/^\[$section\]/,/^\[/ { /vfs objects/d; /full_audit:/d; }" "$file"

    # Adiciona vfs objects com full_audit
    sed -i "/^\[$section\]/a vfs objects = dfs_samba4 acl_xattr full_audit" "$file"

    # Adiciona configurações do full_audit
    sed -i "/^\[$section\]/a full_audit:failure = none\nfull_audit:success = pwrite renameat mkdirat unlinkat fchmod fchown openat\nfull_audit:prefix = IP=%I|USER=%u|MACHINE=%m|VOLUME=%S\nfull_audit:facility = local7\nfull_audit:priority = NOTICE" "$file"
}

log "Configurando auditoria para as shares sysvol e netlogon..."
insert_share_audit "$SMB_CONF" "sysvol"
insert_share_audit "$SMB_CONF" "netlogon"

# --- Configura rsyslog e logrotate para auditoria Samba ---
RSYSLOG_FILE="/etc/rsyslog.d/00-samba-audit.conf"
LOGROTATE_FILE="/etc/logrotate.d/samba-audit"

log "Criando configuração do rsyslog para auditoria..."
cat > "$RSYSLOG_FILE" <<EOF
# Configuração de auditoria do Samba
local7.* /var/log/samba/audit.log
& stop
EOF

log "Criando configuração do logrotate para auditoria..."
cat > "$LOGROTATE_FILE" <<'EOF'
/var/log/samba/audit.log {
    weekly
    missingok
    rotate 8
    compress
    delaycompress
    notifempty
    create 0640 root adm
    postrotate
        /usr/bin/systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF

log "Arquivos de rsyslog e logrotate criados: $RSYSLOG_FILE, $LOGROTATE_FILE"

# Cria diretório de log se não existir
mkdir -p /var/log/samba
chmod 750 /var/log/samba

# Reinicia rsyslog para aplicar a configuração de log
if systemctl restart rsyslog; then
    log "rsyslog reiniciado com sucesso."
else
    log "Aviso: falha ao reiniciar rsyslog"
fi

# --- Hardening Kerberos: ajusta default_etypes conforme manual (já feito acima) ---

# --- Verifica configurações antes de reiniciar ---
log "Verificando sintaxe do smb.conf..."
if testparm -s "$SMB_CONF" >/dev/null 2>&1; then
    log "Sintaxe do smb.conf OK."
else
    error_exit "Erro de sintaxe no smb.conf. Verifique o arquivo $SMB_CONF"
fi

# Reinicia o Samba para aplicar as mudanças
log "Reiniciando serviço samba-ad-dc..."
systemctl restart samba-ad-dc

# Aguarda serviço iniciar
sleep 3

if systemctl is-active --quiet samba-ad-dc; then
    log "Serviço samba-ad-dc reiniciado com sucesso."
    
    # Verifica se o DNS está respondendo
    if nslookup "$HOST" 127.0.0.1 >/dev/null 2>&1; then
        log "DNS respondendo normalmente."
    else
        log "Aviso: DNS pode não estar respondendo corretamente."
    fi
else
    error_exit "Falha ao reiniciar samba-ad-dc. Verifique o log com: journalctl -u samba-ad-dc"
fi

# --- Resumo das configurações aplicadas ---
echo
log "=== RESUMO DO HARDENING APLICADO ==="
echo "=========================================="
echo "1. Configurações smb.conf:"
echo "   • Restrict anonymous = 2"
echo "   • Netbios desabilitado"
echo "   • SMB ports = 445 (apenas)"
echo "   • NTLM auth = mschapv2-and-ntlmv2-only"
echo "   • Server signing = mandatory"
echo "   • SMB encrypt = auto"
echo
echo "2. Políticas de Senha:"
samba_tool_auth domain passwordsettings show | grep -E "Password complexity|Minimum password length|Password history length|Account lockout threshold|Account lockout duration" | sed 's/^/   • /'
echo
echo "3. Configurações Kerberos:"
echo "   • AES256/AES128 configurados como únicos algoritmos"
echo "   • Algoritmos fracos desabilitados"
echo "   • Configuração aplicada no krb5.conf"
echo
echo "4. Auditoria:"
echo "   • full_audit configurado em [global], [sysvol] e [netlogon]"
echo "   • Logs em /var/log/samba/audit.log"
echo "   • Logrotate configurado"
echo
echo "5. DNS:"
echo "   • Registros WPAD/ISATAP removidos"
echo "=========================================="
sleep 5
info_box "Hardening aplicado com sucesso!\n\nServiço Samba reiniciado.\nLogs de auditoria: /var/log/samba/audit.log\n\nBackup do smb.conf: $BACKUP"

exit 0