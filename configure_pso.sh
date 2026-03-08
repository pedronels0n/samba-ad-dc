#!/bin/bash
# configure_pso.sh - Cria PSOs para Admin_Policy e Global_Policy

source "$(dirname "$0")/common.sh"

check_root
check_prereqs samba-tool dialog

# Verifica se o samba-tool está disponível
command -v samba-tool >/dev/null || error_exit "samba-tool não encontrado."

# Credenciais do administrador
ADMIN_USER="${ADMIN_USER:-Administrator}"
ADMIN_PASS="${ADMIN_PASS:-}"

# Se a senha não foi fornecida via ambiente, solicita via dialog
if [ -z "$ADMIN_PASS" ]; then
    # Salva o estado do pipe
    exec 3>&1
    ADMIN_PASS=$(dialog --stdout --title "Senha do Administrador" \
        --passwordbox "Digite a senha do usuário $ADMIN_USER:" 8 50)
    # Restaura e fecha o descritor
    exec 3>&-
    
    # Verifica se a senha foi fornecida
    if [ -z "$ADMIN_PASS" ]; then
        error_exit "Senha não informada."
    fi
fi

# Função para executar samba-tool com autenticação
samba_tool_auth() {
    # Usa --password para evitar prompt interativo
    samba-tool "$@" -U "$ADMIN_USER" --password="$ADMIN_PASS"
}

# Testa autenticação
log "Testando autenticação..."
if ! samba_tool_auth domain info 127.0.0.1 >/dev/null 2>&1; then
    error_exit "Falha na autenticação. Verifique a senha do administrador."
fi
log "Autenticação bem-sucedida!"

# PSO para Administradores (Domain Admins)
log "Criando PSO Admin_Policy..."

# Primeiro, exibe a política atual
echo
log "Política de senha atual do domínio:"
echo "----------------------------------------"
samba_tool_auth domain passwordsettings show || true
echo "----------------------------------------"
echo

# Aplica política GLOBAL conforme manual
log "Aplicando política de senha GLOBAL conforme o manual..."
if ! samba_tool_auth domain passwordsettings set \
    --complexity=on \
    --history-length=24 \
    --min-pwd-length=14 \
    --min-pwd-age=1 \
    --max-pwd-age=90 \
    --account-lockout-threshold=5 \
    --account-lockout-duration=30 \
    --reset-account-lockout-after=30; then
    error_exit "Falha ao aplicar política global de senha."
fi
log "Política global aplicada com sucesso!"

# Cria Admin_Policy
log "Criando PSO Admin_Policy (prioridade 1)..."
if samba_tool_auth domain passwordsettings pso create "Admin_Policy" 1 \
    --complexity=on \
    --min-pwd-length=20 \
    --history-length=30 \
    --account-lockout-threshold=3 \
    --account-lockout-duration=60; then
    log "Admin_Policy criado com sucesso!"
else
    # Verifica se o erro é porque já existe
    if samba_tool_auth domain passwordsettings pso list | grep -q "Admin_Policy"; then
        log "Admin_Policy já existe. Prosseguindo..."
    else
        error_exit "Falha ao criar Admin_Policy."
    fi
fi

# Associa ao grupo Domain Admins
log "Aplicando Admin_Policy ao grupo Domain Admins..."
if samba_tool_auth domain passwordsettings pso apply "Admin_Policy" "Domain Admins"; then
    log "Admin_Policy aplicado ao grupo Domain Admins."
else
    error_exit "Falha ao aplicar Admin_Policy ao grupo Domain Admins."
fi

# PSO para Usuários Globais (todos os usuários do domínio)
log "Criando PSO Global_Policy (prioridade 2)..."
if samba_tool_auth domain passwordsettings pso create "Global_Policy" 2 \
    --complexity=on \
    --min-pwd-length=14 \
    --history-length=20 \
    --account-lockout-threshold=5 \
    --account-lockout-duration=30; then
    log "Global_Policy criado com sucesso!"
else
    # Verifica se o erro é porque já existe
    if samba_tool_auth domain passwordsettings pso list | grep -q "Global_Policy"; then
        log "Global_Policy já existe. Prosseguindo..."
    else
        error_exit "Falha ao criar Global_Policy."
    fi
fi

# Aplica o PSO Global_Policy ao grupo Domain Users
log "Aplicando Global_Policy ao grupo Domain Users..."
if samba_tool_auth domain passwordsettings pso apply "Global_Policy" "Domain Users"; then
    log "Global_Policy aplicado ao grupo Domain Users."
else
    error_exit "Falha ao aplicar Global_Policy ao grupo Domain Users."
fi

# Lista todos os PSOs criados
log "Listando todos os PSOs:"
echo "----------------------------------------"
samba_tool_auth domain passwordsettings pso list || true
echo "----------------------------------------"

# Mostra detalhes do Admin_Policy
log "Detalhes do Admin_Policy:"
echo "----------------------------------------"
samba_tool_auth domain passwordsettings pso show "Admin_Policy" || true
echo "----------------------------------------"

# Mostra detalhes do Global_Policy
log "Detalhes do Global_Policy:"
echo "----------------------------------------"
samba_tool_auth domain passwordsettings pso show "Global_Policy" || true
echo "----------------------------------------"

# Verifica PSOs aplicados ao usuário administrator
log "Verificando PSOs aplicados ao usuário administrator:"
echo "----------------------------------------"
samba_tool_auth domain passwordsettings pso show-user administrator || echo "Usuário administrator não possui PSO específico aplicado"
echo "----------------------------------------"

# Verifica PSOs aplicados a um usuário comum (ex: primeiro usuário não administrador)
TEST_USER=$(samba_tool_auth user list | grep -v "Administrator" | head -1)
if [ -n "$TEST_USER" ]; then
    log "Verificando PSOs aplicados ao usuário $TEST_USER:"
    echo "----------------------------------------"
    samba_tool_auth domain passwordsettings pso show-user "$TEST_USER" || echo "Usuário $TEST_USER não possui PSO específico aplicado"
    echo "----------------------------------------"
fi

# Mostra resumo final
echo
log "=== RESUMO DA CONFIGURAÇÃO ==="
echo "=========================================="
echo "POLÍTICA GLOBAL DO DOMÍNIO:"
samba_tool_auth domain passwordsettings show | grep -E "Password complexity|Minimum password length|Password history length|Account lockout threshold|Account lockout duration" | sed 's/^/  /'
echo
echo "PSOs CRIADOS:"
echo "  • Admin_Policy (prioridade 1) → Domain Admins"
echo "    - Comprimento mínimo: 20 caracteres"
echo "    - Histórico: 30 senhas"
echo "    - Lockout: 3 tentativas, 60 minutos"
echo
echo "  • Global_Policy (prioridade 2) → Domain Users"
echo "    - Comprimento mínimo: 14 caracteres"
echo "    - Histórico: 20 senhas"
echo "    - Lockout: 5 tentativas, 30 minutos"
echo "=========================================="

info_box "PSOs criados e associados com sucesso!\n\nDetalhes:\n\n• Admin_Policy (prioridade 1) → Domain Admins\n  • Comprimento mínimo: 20 caracteres\n  • Histórico: 30 senhas\n  • Lockout: 3 tentativas, 60 minutos\n\n• Global_Policy (prioridade 2) → Domain Users\n  • Comprimento mínimo: 14 caracteres\n  • Histórico: 20 senhas\n  • Lockout: 5 tentativas, 30 minutos\n\n• Política Global do Domínio (fallback)\n  • Comprimento mínimo: 14 caracteres\n  • Histórico: 24 senhas\n  • Lockout: 5 tentativas, 30 minutos\n\nConsulte o console para mais detalhes."

exit 0