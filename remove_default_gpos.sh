#!/bin/bash
# remove_default_gpos.sh - Remove as GPOs padrão do Samba (Default Domain Policy e Default Domain Controllers Policy)
# Baseado no procedimento de Martinsec

source "$(dirname "$0")/common.sh"

check_root
check_prereqs samba-tool ldbsearch ldbdel dialog sed systemctl

# Instala ldb-tools se não estiver presente (necessário para ldbdel/ldbsearch)
if ! command -v ldbdel >/dev/null 2>&1; then
    log "Instalando ldb-tools (apt-get)..."
    apt-get update -y >> "$LOG_FILE" 2>&1 || true
    apt-get install -y ldb-tools >> "$LOG_FILE" 2>&1 || error_exit "Falha ao instalar ldb-tools"
    log "ldb-tools instalado."
fi

# Verifica se o domínio foi provisionado
if [ ! -f /var/lib/samba/private/sam.ldb ]; then
    error_exit "Domínio não provisionado. Execute o provisionamento primeiro."
fi

# Obtém o domínio (DN base)
DOMAIN=$(hostname -d)
if [ -z "$DOMAIN" ]; then
    error_exit "Não foi possível obter o domínio. Hostname está configurado corretamente?"
fi
BASEDN="DC=${DOMAIN//./,DC=}"

# IDs das GPOs padrão
DEFAULT_POLICY_ID="{31B2F340-016D-11D2-945F-00C04FB984F9}"
DEFAULT_DC_POLICY_ID="{6AC1786C-016F-11D2-945F-00C04FB984F9}"

# Confirmação inicial
confirm_box "Este script removerá as duas GPOs padrão do Samba e suas pastas no sysvol.\n\n" \
            "GPOs a remover:\n" \
            "- Default Domain Policy ($DEFAULT_POLICY_ID)\n" \
            "- Default Domain Controllers Policy ($DEFAULT_DC_POLICY_ID)\n\n" \
            "Deseja continuar?"
if [ $? -ne 0 ]; then
    info_box "Operação cancelada."
    exit 0
fi

# Backup do smb.conf antes de qualquer alteração
SMB_CONF="/etc/samba/smb.conf"
BACKUP_SMB="${SMB_CONF}.gpo-removal.bak.$(date +%Y%m%d%H%M%S)"
cp "$SMB_CONF" "$BACKUP_SMB"
log "Backup do smb.conf criado em $BACKUP_SMB"

# --- Fase 2: Remoção temporária do full_audit ---
log "Removendo temporariamente full_audit das seções [sysvol] e [netlogon]..."
sed -i '/^\[sysvol\]/,/^\[/ s/vfs objects = dfs_samba4 acl_xattr full_audit/vfs objects = dfs_samba4 acl_xattr/' "$SMB_CONF"
sed -i '/^\[netlogon\]/,/^\[/ s/vfs objects = dfs_samba4 acl_xattr full_audit/vfs objects = dfs_samba4 acl_xattr/' "$SMB_CONF"

log "Reiniciando Samba para aplicar a remoção do full_audit..."
systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1
if ! systemctl is-active samba-ad-dc >/dev/null; then
    error_exit "Falha ao reiniciar Samba após remover full_audit."
fi

# --- Redefinição das permissões do sysvol ---
log "Executando samba-tool ntacl sysvolreset..."
samba-tool -U Administrator ntacl sysvolreset 
if [ $? -ne 0 ]; then
    error_exit "Falha ao executar sysvolreset."
fi

# Lista as GPOs atuais para conferência (conforme manual)
log "Listando GPOs atuais (samba-tool gpo listall)..."
samba-tool -U Administrator gpo listall 
# --- Exclusão dos objetos no banco de dados (ldbdel) ---
LDB_DEL="ldbdel -H /var/lib/samba/private/sam.ldb --relax"

# Função para deletar um DN se existir
delete_ldb() {
    local dn="$1"
    local description="$2"
    if ldbsearch -H /var/lib/samba/private/sam.ldb -b "$dn" >/dev/null 2>&1; then
        log "Deletando $description: $dn"
        $LDB_DEL "$dn" >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log "OK: $description removido."
        else
            error_exit "Falha ao deletar $description"
        fi
    else
        log "Aviso: $description não encontrado no LDAP. Pulando."
    fi
}

# Deletar objetos da Default Domain Policy
delete_ldb "CN=User,CN=$DEFAULT_POLICY_ID,CN=Policies,CN=System,$BASEDN" "User da Default Policy"
delete_ldb "CN=Machine,CN=$DEFAULT_POLICY_ID,CN=Policies,CN=System,$BASEDN" "Machine da Default Policy"
delete_ldb "CN=$DEFAULT_POLICY_ID,CN=Policies,CN=System,$BASEDN" "Container da Default Policy"

# Deletar objetos da Default Domain Controllers Policy
delete_ldb "CN=User,CN=$DEFAULT_DC_POLICY_ID,CN=Policies,CN=System,$BASEDN" "User da Default DC Policy"
delete_ldb "CN=Machine,CN=$DEFAULT_DC_POLICY_ID,CN=Policies,CN=System,$BASEDN" "Machine da Default DC Policy"
delete_ldb "CN=$DEFAULT_DC_POLICY_ID,CN=Policies,CN=System,$BASEDN" "Container da Default DC Policy"

# --- Exclusão das pastas no sysvol ---
SYSVOL_POLICIES="/var/lib/samba/sysvol/$DOMAIN/Policies"
log "Removendo pastas físicas em $SYSVOL_POLICIES..."
if [ -d "$SYSVOL_POLICIES/$DEFAULT_POLICY_ID" ]; then
    rm -rf "$SYSVOL_POLICIES/$DEFAULT_POLICY_ID"
    log "Pasta $DEFAULT_POLICY_ID removida."
else
    log "Pasta $DEFAULT_POLICY_ID não encontrada."
fi
if [ -d "$SYSVOL_POLICIES/$DEFAULT_DC_POLICY_ID" ]; then
    rm -rf "$SYSVOL_POLICIES/$DEFAULT_DC_POLICY_ID"
    log "Pasta $DEFAULT_DC_POLICY_ID removida."
else
    log "Pasta $DEFAULT_DC_POLICY_ID não encontrada."
fi

# --- Fim: restauração do full_audit será feita depois da criação das novas GPOs (opção separada) ---

info_box "GPOs padrão removidas com sucesso!\n\n" \
         "As configurações de auditoria (full_audit) ainda estão desabilitadas.\n" \
         "Após criar as novas GPOs e importar os templates, execute a opção de finalização para restaurar o full_audit e aplicar criptografia SMB."