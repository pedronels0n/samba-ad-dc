#!/bin/bash
# samba_restore.sh - Script interativo para restauração de desastre do Samba AD DC
# Compatível com Ubuntu Server.
# Deve ser executado em um servidor novo com mesmo IP e hostname do antigo DC.

source "$(dirname "$0")/common.sh"

check_root
check_dialog
# ferramentas utilizadas durante a restauração
check_prereqs tar find dialog systemctl samba
# ferramentas utilizadas durante a restauração
check_prereqs tar find dialog systemctl samba

# Verifica se o backup existe
BACKUP_FILE=""
while [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; do
    BACKUP_FILE=$(dialog --stdout --title "Arquivo de Backup" \
        --inputbox "Digite o caminho completo do arquivo de backup (ex: /opt/samba04_backup.tar.gz):" 10 60)
    [ $? -ne 0 ] && exit 0
    if [ ! -f "$BACKUP_FILE" ]; then
        dialog --title "Erro" --msgbox "Arquivo não encontrado. Tente novamente." 6 40
    fi
done

# Extrai informações de versão do backup
INFO_TMP=$(mktemp)
tar -xOvf "$BACKUP_FILE" etc/samba/info_versions_backup > "$INFO_TMP" 2>/dev/null
if [ $? -ne 0 ] || [ ! -s "$INFO_TMP" ]; then
    rm -f "$INFO_TMP"
    error_exit "Não foi possível extrair as informações de versão do backup. Backup corrompido?"
fi

# Mostra as versões e solicita confirmação
dialog --title "Informações do Backup" --textbox "$INFO_TMP" 20 70

# Extrai a versão do Samba
SAMBA_VERSION=$(grep -i "samba version" "$INFO_TMP" | head -1 | awk '{print $3}')
if [ -z "$SAMBA_VERSION" ]; then
    SAMBA_VERSION="desconhecida"
fi
rm -f "$INFO_TMP"

confirm_box "A restauração irá substituir completamente a configuração atual.\n\n" \
            "Versão do Samba no backup: $SAMBA_VERSION\n\n" \
            "Certifique-se de que este servidor tem o mesmo IP e hostname do antigo DC.\n" \
            "Deseja continuar?"
[ $? -ne 0 ] && exit 0

# --- Verificação da versão do Samba instalada ---
if command -v samba >/dev/null; then
    INSTALLED_VERSION=$(samba --version | awk '{print $2}')
else
    INSTALLED_VERSION="não instalado"
fi

if [ "$INSTALLED_VERSION" != "$SAMBA_VERSION" ] && [ "$INSTALLED_VERSION" != "não instalado" ]; then
    dialog --title "Aviso de Versão" --yesno "A versão do Samba instalada ($INSTALLED_VERSION) é diferente da versão do backup ($SAMBA_VERSION).\n\nA restauração pode falhar se as versões não forem compatíveis.\n\nDeseja continuar mesmo assim?" 12 60
    if [ $? -ne 0 ]; then
        info_box "Recomenda-se instalar a versão $SAMBA_VERSION do Samba antes de prosseguir.\n\nNo Ubuntu, você pode baixar o pacote .deb correspondente do Launchpad (https://launchpad.net/ubuntu/+source/samba) e instalar manualmente com 'dpkg -i'.\n\nApós a instalação da versão correta, execute este script novamente."
        exit 0
    fi
fi

# Se o Samba não estiver instalado, pergunta se deseja instalar agora
if [ "$INSTALLED_VERSION" = "não instalado" ]; then
    if confirm_box "O Samba não está instalado. Deseja instalar a versão $SAMBA_VERSION agora?\n\n(Isso requer acesso à internet e pode precisar de repositórios adequados.)"; then
        # Tenta instalar a versão exata (simplificado: instala a versão disponível nos repositórios e alerta)
        apt update
        apt install -y samba krb5-config krb5-user winbind smbclient ldb-tools
        # Após instalar, verifica a versão
        NEW_VERSION=$(samba --version | awk '{print $2}')
        if [ "$NEW_VERSION" != "$SAMBA_VERSION" ]; then
            dialog --title "Aviso" --msgbox "A versão instalada ($NEW_VERSION) difere da versão do backup ($SAMBA_VERSION).\nA restauração pode falhar." 10 60
        fi
    else
        info_box "Instale o Samba manualmente com a versão correta e execute este script novamente."
        exit 0
    fi
fi

# --- 1. Instala pacotes básicos (chrony, rsyslog) ---
dialog --infobox "Instalando pacotes básicos (chrony, rsyslog)..." 5 60
apt update >> "$LOG_FILE" 2>&1
apt install -y chrony rsyslog >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    error_exit "Falha na instalação dos pacotes básicos."
fi

# --- 2. Verifica hostname ---
DOMAIN=$(hostname -d)
if [ -z "$DOMAIN" ]; then
    dialog --title "Aviso" --msgbox "O hostname atual não parece ser um FQDN (domínio não detectado).\nConfigure o hostname e /etc/hosts antes de prosseguir.\n\nHostname atual: $(hostname -f)" 10 60
    confirm_box "Deseja continuar mesmo assim?" || exit 0
else
    log "Hostname OK: $(hostname -f)"
fi

# --- 3. Parada de serviços e remoção de configurações padrão ---
dialog --infobox "Parando serviços e limpando configurações existentes..." 5 60
systemctl stop smbd nmbd winbind 2>/dev/null
systemctl disable smbd nmbd winbind 2>/dev/null
systemctl mask smbd nmbd winbind 2>/dev/null

# Remove arquivos de configuração padrão
rm -rf /etc/samba/* /var/lib/samba/* /var/cache/samba/* /etc/krb5.conf

# --- 4. Extração do backup ---
dialog --infobox "Extraindo backup para a raiz (/) ..." 5 60
if tar --xattrs --acls -xzpvf "$BACKUP_FILE" -C / >> "$LOG_FILE" 2>&1; then
    log "Backup extraído com sucesso."
else
    error_exit "Falha na extração do backup."
fi

# --- 5. Configuração do resolv.conf ---
dialog --infobox "Configurando /etc/resolv.conf..." 5 60
cat > /etc/resolv.conf <<EOF
domain $DOMAIN
search $DOMAIN
nameserver 127.0.0.1
EOF
chattr +i /etc/resolv.conf

# --- 6. Habilita e inicia samba-ad-dc ---
dialog --infobox "Habilitando e iniciando samba-ad-dc..." 5 60
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc
sleep 5
if ! systemctl is-active samba-ad-dc >/dev/null; then
    error_exit "Falha ao iniciar samba-ad-dc. Verifique o log."
fi

# --- 7. Validações pós-restore ---
dialog --infobox "Executando validações pós-restore..." 5 60
{
    echo "=== Validações Pós-Restore ==="
    echo "Data: $(date)"
    echo
    echo "--- dbcheck ---"
    samba-tool dbcheck --cross-ncs
    echo
    echo "--- showrepl ---"
    samba-tool drs showrepl
    echo
    echo "--- domain level ---"
    samba-tool domain level show
    echo
    echo "--- user list ---"
    samba-tool user list | head -10
    echo
    echo "--- DNS SRV _ldap ---"
    host -t SRV _ldap._tcp.$DOMAIN
} > /tmp/samba-restore-check.txt 2>&1

dialog --title "Resultado da Validação Pós-Restore" --textbox /tmp/samba-restore-check.txt 20 80
rm /tmp/samba-restore-check.txt

# --- 8. Restauração opcional dos logs de auditoria ---
if confirm_box "Deseja restaurar a configuração de logs de auditoria (rsyslog e logrotate)?"; then
    cat > /etc/rsyslog.d/00-samba-audit.conf <<'EOF'
local7.* /var/log/samba/audit.log
& stop
EOF
    cat > /etc/logrotate.d/samba-audit <<'EOF'
/var/log/samba/audit.log {
    weekly
    missingok
    rotate 8
    compress
    delaycompress
    notifempty
    postrotate
        /usr/bin/systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
    systemctl restart rsyslog
    dialog --msgbox "Configuração de logs de auditoria restaurada." 6 40
fi

info_box "Restauração concluída com sucesso!\nRecomenda-se reiniciar o servidor para garantir que todos os serviços iniciem corretamente."

exit 0