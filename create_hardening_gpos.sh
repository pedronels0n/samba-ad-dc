#!/bin/bash
# create_hardening_gpos.sh - Cria as GPOs de hardening a partir da lista

source "$(dirname "$0")/common.sh"

check_root

# Verifica se o samba-tool está disponível
command -v samba-tool >/dev/null || error_exit "samba-tool não encontrado."

# Solicita a senha do Administrator (duas vezes para confirmação)
exec 3>&1
ADMIN_PASS=$(dialog --stdout --title "Senha do Administrator" \
    --passwordbox "Digite a senha do usuário Administrator do domínio:" 8 50)
[ -z "$ADMIN_PASS" ] && error_exit "Senha não informada."

ADMIN_PASS2=$(dialog --stdout --title "Confirme a senha" \
    --passwordbox "Digite a senha novamente:" 8 50)
[ "$ADMIN_PASS" != "$ADMIN_PASS2" ] && error_exit "As senhas não conferem."

# Lista exata das GPOs a criar
GPOS=(
    "PC_WinServer IE 11 PC"
    "User_WinServer IE 11 User"
    "PC_WinServer Def Antivirus"
    "DC_WinServer DC"
    "DC_WinServer DC Sec"
    "PC_WinServer MS"
    "PC_Win10 IE 11 PC"
    "User_Win10 IE 11 User"
    "PC_Win10 Bitlocker"
    "PC_Win10 PC"
    "PC_Win10 Defender Antivirus"
    "PC_Win10 Domain Sec"
    "User_Win10 User"
    "PC_Win11 IE 11 PC"
    "PC_Win11 IE 11 User"
    "PC_Win11 Bitlocker"
    "PC_Win11 PC"
    "PC_Win11 Defender Antivirus"
    "PC_Win11 Domain Sec"
    "User_Win11 User"
)

TOTAL=${#GPOS[@]}
CURRENT=0
FAILED=()

# Criação com barra de progresso (dialog --gauge)
for GPO in "${GPOS[@]}"; do
    PERCENT=$((CURRENT * 100 / TOTAL))
    echo "$PERCENT" | dialog --gauge "Criando GPO: $GPO\n($CURRENT de $TOTAL concluídas)" 8 70 0

    log "Criando GPO: $GPO"
    samba-tool gpo create "$GPO" -U Administrator --password="$ADMIN_PASS" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log "ERRO: Falha ao criar GPO '$GPO'"
        FAILED+=("$GPO")
    fi
    ((CURRENT++))
done

# Mensagem final
if [ ${#FAILED[@]} -eq 0 ]; then
    info_box "Todas as $TOTAL GPOs foram criadas com sucesso!"
else
    MSG="Algumas GPOs falharam:\n"
    for f in "${FAILED[@]}"; do
        MSG+="- $f\n"
    done
    MSG+="\nVerifique o log em $LOG_FILE"
    info_box "$MSG"
fi