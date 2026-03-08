#!/bin/bash
# provision_domain.sh - Provisiona o domínio Samba AD

source "$(dirname "$0")/common.sh"

check_root

# Verifica se o Samba já está provisionado
if [ -f /var/lib/samba/private/sam.ldb ]; then
    confirm_box "O Samba já parece estar provisionado. Deseja continuar assim mesmo? Isso pode sobrescrever configurações."
    if [ $? -ne 0 ]; then
        info_box "Provisionamento cancelado."
        exit 0
    fi
fi

# Solicita dados do domínio
exec 3>&1
DOMAIN=$(dialog --stdout --title "Provisionamento do Domínio" \
    --inputbox "Digite o nome do domínio (ex: exemplo.local):" 8 50)
[ -z "$DOMAIN" ] && error_exit "Domínio não informado."

REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
DOMAIN_SHORT="${DOMAIN%%.*}"

ADMIN_PASS=$(dialog --stdout --title "Senha do Administrador" \
    --passwordbox "Digite a senha do administrador do domínio:" 8 50)
[ -z "$ADMIN_PASS" ] && error_exit "Senha não informada."

ADMIN_PASS2=$(dialog --stdout --title "Confirme a Senha" \
    --passwordbox "Digite a senha novamente:" 8 50)
[ "$ADMIN_PASS" != "$ADMIN_PASS2" ] && error_exit "As senhas não conferem."

# Confirma os dados
dialog --title "Resumo do Provisionamento" \
    --yesno "Domínio: $DOMAIN\nRealm: $REALM\n\nConfirma os dados?" 8 50
if [ $? -ne 0 ]; then
    info_box "Provisionamento cancelado."
    exit 0
fi

# Para o Samba se estiver rodando
log "Parando serviços do Samba..."
systemctl stop samba-ad-dc 2>/dev/null || true
systemctl stop smbd nmbd winbind 2>/dev/null || true
sleep 2
systemctl stop samba 2>/dev/null || true
sleep 2

log "Serviços parados."

# Backup do smb.conf atual e remoção para garantir que não haja interferência
if [ -f /etc/samba/smb.conf ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)
    log "Backup do /etc/samba/smb.conf criado."
    rm -f /etc/samba/smb.conf
    log "Arquivo smb.conf removido para provisionamento limpo."
fi

# Provisiona o domínio
log "Iniciando provisionamento do domínio $DOMAIN..."
samba-tool domain provision \
    --use-rfc2307 \
    --realm="$REALM" \
    --domain="$DOMAIN_SHORT" \
    --adminpass="$ADMIN_PASS" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL 

log "Provisionamento concluído com sucesso."

# Obtém o IP do servidor
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)
if [ -z "$SERVER_IP" ]; then
    error_exit "Não foi possível determinar o IP do servidor."
fi

log "Adicionando configurações de interface ao smb.conf..."
# Adiciona as configurações de interfaces após a seção [global]
sed -i "/^\[global\]/a\    bind interfaces only = yes\n    interfaces = lo $SERVER_IP" /etc/samba/smb.conf

log "Configurações de interface adicionadas com sucesso."
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc

info_box "Domínio provisionado com sucesso!\nRealm: $REALM\nDomínio: $DOMAIN"