#!/bin/bash
# raise_functional_level.sh - Eleva o nível funcional do domínio/floresta para 2016
# Segue o procedimento: adicionar smb.conf, schemaupgrade, functionalprep, level raise

source "$(dirname "$0")/common.sh"

check_root

# Verifica se o domínio já foi provisionado
if [ ! -f /var/lib/samba/private/sam.ldb ]; then
    error_exit "Domínio não provisionado. Execute o provisionamento primeiro."
fi

# Mostra nível atual
echo "Níveis atuais:" > /tmp/current_levels.txt
samba-tool domain level show >> /tmp/current_levels.txt 2>&1
dialog --title "Níveis Atuais" --textbox /tmp/current_levels.txt 12 50
rm /tmp/current_levels.txt

# Confirma a elevação para 2016
confirm_box "Este procedimento irá:\n\n" \
            "1. Adicionar 'ad dc functional level = 2016' no smb.conf\n" \
            "2. Executar schemaupgrade --schema=2019\n" \
            "3. Executar functionalprep --function-level=2016\n" \
            "4. Elevar domínio e floresta para 2016\n\n" \
            "Esta operação é irreversível. Deseja continuar?"
if [ $? -ne 0 ]; then
    info_box "Operação cancelada."
    exit 0
fi

# Backup do smb.conf
SMB_CONF="/etc/samba/smb.conf"
BACKUP="${SMB_CONF}.levelup.bak.$(date +%Y%m%d%H%M%S)"
cp "$SMB_CONF" "$BACKUP"
log "Backup do smb.conf criado em $BACKUP"

# Adiciona ou substitui a diretiva ad dc functional level
if grep -q "^[[:space:]]*ad dc functional level" "$SMB_CONF"; then
    sed -i 's/^[[:space:]]*ad dc functional level.*/ad dc functional level = 2016/' "$SMB_CONF"
else
    sed -i '/^\[global\]/a ad dc functional level = 2016' "$SMB_CONF"
fi
log "Diretiva 'ad dc functional level = 2016' adicionada ao smb.conf."

# Executa schemaupgrade
log "Executando samba-tool domain schemaupgrade --schema=2019..."
samba-tool domain schemaupgrade --schema=2019 >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    error_exit "Falha no schemaupgrade. Verifique o log."
fi
log "Schemaupgrade concluído."

# Executa functionalprep
log "Executando samba-tool domain functionalprep --function-level=2016..."
samba-tool domain functionalprep --function-level=2016 >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    error_exit "Falha no functionalprep. Verifique o log."
fi
log "Functionalprep concluído."

# Eleva nível do domínio e floresta
log "Elevando nível do domínio e floresta para 2016..."
samba-tool domain level raise --domain-level=2016 --forest-level=2016 >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    log "Níveis elevados com sucesso."
else
    error_exit "Falha ao elevar níveis."
fi

# Validação final
{
    echo "Níveis após elevação:"
    samba-tool domain level show
} > /tmp/new_levels.txt
dialog --title "Níveis Atualizados" --textbox /tmp/new_levels.txt 12 50
rm /tmp/new_levels.txt

# Reinicia o Samba
log "Reiniciando samba-ad-dc..."
systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1
if systemctl is-active samba-ad-dc >/dev/null; then
    info_box "Nível funcional elevado para 2016 e serviço reiniciado com sucesso."
else
    error_exit "Falha ao reiniciar samba-ad-dc após elevação."
fi