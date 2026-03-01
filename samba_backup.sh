#!/bin/bash
# samba_backup.sh - Script de backup automático para Samba AD DC (Single-DC)
# Compatível com Ubuntu Server e Debian.
# Utiliza funções do common.sh (log, info_box, confirm_box)

source "$(dirname "$0")/common.sh"

# Verifica root
check_root

# --- Variáveis de Configuração ---
BACKUP_DIR="/opt/samba_backups"
LOG_FILE="${LOG_FILE:-/var/log/samba_backup.log}"  # usa o mesmo LOG_FILE do common ou define padrão
RETENTION_DAYS=7
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/samba04_backup_${TIMESTAMP}.tar.gz"

# Garante que o diretório de backup existe
mkdir -p "$BACKUP_DIR"

log "========================================================="
log "Iniciando rotina de backup do Samba AD DC..."

# --- 1. Validação de Integridade do Banco (Pré-requisito) ---
log "Executando verificação de consistência (dbcheck)..."
if ! samba-tool dbcheck --cross-ncs >> "$LOG_FILE" 2>&1; then
    log "[CRÍTICO] O dbcheck falhou! Banco de dados possivelmente corrompido."
    log "[CRÍTICO] Backup abortado para evitar a cópia de dados inconsistentes."
    error_exit "Backup abortado devido a falha no dbcheck."
fi
log "Integridade do banco validada com sucesso."

# --- 2. Parada dos Serviços ---
log "Parando os serviços do Samba..."
systemctl stop samba-ad-dc smbd nmbd winbind
sleep 3  # Aguarda liberação dos arquivos

# --- 3. Coleta de Metadados de Versão ---
log "Coletando versões do SO e do Samba para o arquivo info_versions_backup..."
INFO_FILE="/etc/samba/info_versions_backup"
{
    echo "=== SAMBA VERSION ==="
    samba --version
    echo -e "\n=== OS VERSION ==="
    cat /etc/*-release
    echo -e "\n=== DATA DO BACKUP ==="
    date
} > "$INFO_FILE"

# --- 4. Geração do Arquivo de Backup ---
log "Criando arquivo de backup compactado (tar)..."
# Usar --xattrs --acls é essencial para preservar permissões do sysvol
if tar --xattrs --acls -czpvf "$BACKUP_FILE" \
    /etc/samba \
    /var/lib/samba \
    /var/cache/samba \
    /etc/krb5.conf \
    "$INFO_FILE" >> "$LOG_FILE" 2>&1; then
    log "Backup criado com sucesso em: $BACKUP_FILE"
else
    log "[ERRO] Falha ao criar o arquivo compactado."
    log "Reiniciando serviços antes de abortar..."
    systemctl start samba-ad-dc
    error_exit "Falha na criação do backup."
fi

# --- 5. Reinicialização dos Serviços ---
log "Iniciando serviços do Samba..."
systemctl start samba-ad-dc

# --- 6. Política de Retenção (Limpeza) ---
log "Aplicando política de retenção (Removendo backups com mais de $RETENTION_DAYS dias)..."
find "$BACKUP_DIR" -type f -name "samba04_backup_*.tar.gz" -mtime +$RETENTION_DAYS -exec rm -f {} \; -exec log "Backup antigo removido: {}" \;

log "Rotina de backup concluída com sucesso."
log "========================================================="

# Mensagem opcional via dialog se for executado interativamente
if [ -t 1 ]; then
    info_box "Backup concluído com sucesso!\nArquivo: $BACKUP_FILE\nBackup armazenado em: $BACKUP_DIR"
fi

exit 0