#!/bin/bash
# configure_pso.sh - Cria PSOs para Admin_Policy e Global_Policy

source "$(dirname "$0")/common.sh"

check_root
check_prereqs samba-tool dialog

# Verifica se o samba-tool está disponível
command -v samba-tool >/dev/null || error_exit "samba-tool não encontrado."

# PSO para Administradores (Domain Admins)
log "Criando PSO Admin_Policy..."
# Primeiro, exibe a política atual
samba-tool -U Administrator domain passwordsettings show || true

# Aplica política GLOBAL conforme manual
log "Aplicando política de senha GLOBAL conforme o manual..."
samba-tool -U Administrator domain passwordsettings set \
    --complexity=on \
    --history-length=24 \
    --min-pwd-length=14 \
    --min-pwd-age=1 \
    --max-pwd-age=90 \
    --account-lockout-threshold=5 \
    --account-lockout-duration=30 \
    --reset-account-lockout-after=30

log "Criando PSO Admin_Policy..."
samba-tool -U Administrator domain passwordsettings pso create "Admin_Policy" 1 \
    --complexity=on \
    --min-pwd-length=20 \
    --history-length=30 \
    --account-lockout-threshold=3 \
    --account-lockout-duration=60 

# Verifica criação
if [ $? -ne 0 ]; then
    error_exit "Falha ao criar Admin_Policy."
fi

# Associa ao grupo Domain Admins (usando nome do grupo compatível com o manual)
samba-tool -U Administrator domain passwordsettings pso apply "Admin_Policy" "Domain Admins"
if [ $? -eq 0 ]; then
    log "Admin_Policy aplicado ao grupo Domain Admins."
else
    error_exit "Falha ao aplicar Admin_Policy."
fi

# PSO para Usuários Globais (todos os usuários do domínio)
log "Criando PSO Global_Policy..."
samba-tool -U Administrator domain passwordsettings pso create "Global_Policy" 2 \
    --complexity=on \
    --min-pwd-length=14 \
    --history-length=20 \
    --account-lockout-threshold=5 \
    --account-lockout-duration=30
 
if [ $? -ne 0 ]; then
    error_exit "Falha ao criar Global_Policy."
fi

# Aplica o PSO Global_Policy ao grupo Domain Users
samba-tool -U Administrator domain passwordsettings pso apply "Global_Policy" "Domain Users"
if [ $? -eq 0 ]; then
    log "Global_Policy aplicado ao grupo Domain Users."
else
    error_exit "Falha ao aplicar Global_Policy."
fi

# Confirmação: mostra se o PSO está aplicado ao usuário administrator
samba-tool -U Administrator domain passwordsettings pso show-user administrator || log "Falha ao mostrar PSO do usuário administrator"

info_box "PSOs criados e associados:\n- Admin_Policy (prioridade 1) → Domain Admins\n- Global_Policy (prioridade 2) → Domain Users"