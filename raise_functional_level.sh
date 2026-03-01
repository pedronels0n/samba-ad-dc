#!/bin/bash
# raise_functional_level.sh - Eleva o nível funcional do domínio/floresta

source "$(dirname "$0")/common.sh"

check_root

# Verifica se o domínio já foi provisionado
if [ ! -f /var/lib/samba/private/sam.ldb ]; then
    error_exit "Domínio não provisionado. Execute o provisionamento primeiro."
fi

# Mostra nível atual
CURRENT_DOMAIN_LEVEL=$(samba-tool domain level show | grep "Domain" | awk '{print $NF}')
CURRENT_FOREST_LEVEL=$(samba-tool domain level show | grep "Forest" | awk '{print $NF}')

info_box "Níveis atuais:\nDomínio: $CURRENT_DOMAIN_LEVEL\nFloresta: $CURRENT_FOREST_LEVEL"

# Menu de escolha do novo nível
LEVEL=$(dialog --stdout --title "Nível Funcional" \
    --menu "Escolha o novo nível funcional (requer que todos os DCs estejam atualizados):" 12 50 3 \
    1 "2008 R2" \
    2 "2012" \
    3 "2012 R2")

case $LEVEL in
    1) NEW_LEVEL="2008_R2" ;;
    2) NEW_LEVEL="2012" ;;
    3) NEW_LEVEL="2012_R2" ;;
    *) exit 0 ;;
esac

confirm_box "Elevar domínio para $NEW_LEVEL? Esta operação é irreversível."
if [ $? -ne 0 ]; then
    info_box "Operação cancelada."
    exit 0
fi

log "Elevando nível do domínio para $NEW_LEVEL..."
samba-tool domain level raise --domain-level="$NEW_LEVEL" >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    log "Elevando nível da floresta para $NEW_LEVEL..."
    samba-tool domain level raise --forest-level="$NEW_LEVEL" >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        info_box "Níveis elevados para $NEW_LEVEL com sucesso."
    else
        error_exit "Falha ao elevar nível da floresta."
    fi
else
    error_exit "Falha ao elevar nível do domínio."
fi