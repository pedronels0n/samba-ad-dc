#!/bin/bash
# configure_pso.sh - Cria PSOs para Admin_Policy e Global_Policy

source "$(dirname "$0")/common.sh"

check_root
check_prereqs samba-tool dialog

# Verifica se o samba-tool está disponível
command -v samba-tool >/dev/null || error_exit "samba-tool não encontrado."

# PSO para Administradores (Domain Admins)
log "Criando PSO Admin_Policy..."
samba-tool domain passwordsettings pso create "Admin_Policy" 1 \
    --min-pwd-length=14 \
    --pwd-history-length=30 \
    --lockout-threshold=3 \
    --lockout-duration=60 \
    --lockout-window=30 \
    >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    error_exit "Falha ao criar Admin_Policy."
fi

# Associa ao grupo Domain Admins
samba-tool domain passwordsettings pso apply "Admin_Policy" "CN=Domain Admins,CN=Users,DC=$(hostname -d | sed 's/\./,DC=/g')" >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    log "Admin_Policy aplicado ao grupo Domain Admins."
else
    error_exit "Falha ao aplicar Admin_Policy."
fi

# PSO para Usuários Globais (todos os usuários do domínio)
log "Criando PSO Global_Policy..."
samba-tool domain passwordsettings pso create "Global_Policy" 2 \
    --min-pwd-length=8 \
    --pwd-history-length=20 \
    --lockout-threshold=5 \
    --lockout-duration=30 \
    --lockout-window=30 \
    >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    error_exit "Falha ao criar Global_Policy."
fi

# Associa ao grupo Domain Users
samba-tool domain passwordsettings pso apply "Global_Policy" "CN=Domain Users,CN=Users,DC=$(hostname -d | sed 's/\./,DC=/g')" >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    log "Global_Policy aplicado ao grupo Domain Users."
else
    error_exit "Falha ao aplicar Global_Policy."
fi

info_box "PSOs criados e associados:\n- Admin_Policy (prioridade 1) → Domain Admins\n- Global_Policy (prioridade 2) → Domain Users"