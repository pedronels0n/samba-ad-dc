#!/bin/bash
# configure_services.sh - Configura os serviços do Samba DC

source "$(dirname "$0")/common.sh"

# Verifica root
check_root
check_prereqs systemctl dialog

log "Parando serviços não necessários (smbd, nmbd, winbind)..."
systemctl stop smbd nmbd winbind 2>/dev/null
systemctl disable smbd nmbd winbind 2>/dev/null

log "Habilitando e iniciando samba-ad-dc..."
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc

# Verifica se o serviço iniciou corretamente
if systemctl is-active samba-ad-dc >/dev/null; then
    log "Serviço samba-ad-dc iniciado com sucesso."
    info_box "Serviços configurados:\n- samba-ad-dc ativo\n- smbd/nmbd/winbind desabilitados"
else
    error_exit "Falha ao iniciar samba-ad-dc. Verifique o log."
fi