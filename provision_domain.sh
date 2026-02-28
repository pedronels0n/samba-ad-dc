#!/bin/bash
# provision_domain.sh - Provisiona o domínio no Samba

source "$(dirname "$0")/common.sh"

# Verifica root
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

ADMIN_PASS=$(dialog --stdout --title "Senha do Administrador" \
    --passwordbox "Digite a senha do administrador do domínio:" 8 50)
[ -z "$ADMIN_PASS" ] && error_exit "Senha não informada."

# Confirma a senha
ADMIN_PASS2=$(dialog --stdout --title "Confirme a Senha" \
    --passwordbox "Digite a senha novamente:" 8 50)
[ "$ADMIN_PASS" != "$ADMIN_PASS2" ] && error_exit "As senhas não conferem."

# Para o Samba se estiver rodando
systemctl stop samba-ad-dc smbd nmbd winbind 2>/dev/null

# Remove configurações antigas (backup)
if [ -f /etc/samba/smb.conf ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)
fi

# Provisiona o domínio
log "Iniciando provisionamento do domínio $DOMAIN..."
samba-tool domain provision \
    --use-rfc2307 \
    --realm="$REALM" \
    --domain="${DOMAIN%%.*}" \
    --adminpass="$ADMIN_PASS" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --function-level=2008_R2 \
    >> "$LOG_FILE" 2>&1 || error_exit "Falha no provisionamento."

# Move o smb.conf gerado para o local correto (já está em /etc/samba/smb.conf pelo provisionamento)
log "Provisionamento concluído com sucesso."

# Configura o serviço samba-ad-dc
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc

info_box "Domínio provisionado com sucesso!\nRealm: $REALM\nDomínio: $DOMAIN"