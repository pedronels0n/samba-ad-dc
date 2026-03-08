#!/bin/bash
# configure_services.sh - Configura os serviços do Samba DC

source "$(dirname "$0")/common.sh"

# Verifica root
check_root
check_prereqs systemctl dialog

log "Parando serviços não necessários (smbd, nmbd, winbind)..."
systemctl stop smbd nmbd winbind 2>/dev/null || true
systemctl disable smbd nmbd winbind 2>/dev/null || true

log "Habilitando e iniciando samba-ad-dc..."
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl restart samba-ad-dc
sleep 3

# Verifica se o serviço iniciou corretamente
if systemctl is-active --quiet samba-ad-dc; then
    log "Serviço samba-ad-dc iniciado com sucesso."
    
    # Verifica se o Samba está funcional com samba-tool
    if samba-tool forest info localhost > /dev/null 2>&1; then
        log "Verificação de forest info bem-sucedida."
        info_box "✔ Serviços configurados adequadamente:\n\
- samba-ad-dc ativo e funcional\n\
- smbd/nmbd/winbind desabilitados\n\n\
Seu AD DC está pronto para aceitar clientes!"
    else
        log "AVISO: samba-tool forest info falhou. Verifique os logs."
        info_box "⚠ Serviços iniciados, mas verifique:\n\
journalctl -u samba-ad-dc -n 50"
    fi
else
    log "ERRO: samba-ad-dc não está ativo."
    systemctl status samba-ad-dc
    error_exit "Falha ao iniciar samba-ad-dc. Verifique o log: journalctl -u samba-ad-dc"
fi