#!/bin/bash
# ==========================================================
#  Samba AD DC Automation Framework
#  Console Interativo de Implantação
#  @pedronels0n development
#  Versão: 2.3.0 (com suporte a backup/restore)
# ==========================================================

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/common.sh"

check_root
check_dialog
# o menu usa dialog, samba-tool, systemctl, etc.

show_banner() {
    clear
    echo "=============================================================="
    echo "         SAMBA ACTIVE DIRECTORY DEPLOYMENT CONSOLE           "
    echo "=============================================================="
    echo "  Autor: @pedronels0n development"
    echo "  Host:  $(hostname -f)"
    echo "  Data:  $(date '+%d/%m/%Y %H:%M:%S')"
    echo "=============================================================="
    echo
}

while true; do
    show_banner

    CHOICE=$(dialog --clear --stdout \
        --backtitle "Samba AD DC Automation Framework v2.3.0 | @pedronels0n development" \
        --title "Menu Principal" \
        --menu "Selecione uma opção:" 38 100 30 \
        1  "Configurar Hostname (FQDN)" \
        2  "Configurar IP Fixo (Rede)" \
        3  "Configurar /etc/resolv.conf (DNS)" \
        4  "Instalar Pacotes Necessários" \
        5  "Configurar Sincronização de Hora (Chrony)" \
        6  "Configurar Kerberos" \
        7  "Provisionar Domínio Active Directory" \
        8  "Configurar e Habilitar Serviços" \
        "-" "-------------------- CONFIGURAÇÕES AVANÇADAS --------------------" \
        9  "Elevar Nível Funcional do Domínio" \
        10 "Configurar Zona DNS Reversa" \
        11 "Criar Políticas de Senha (PSO)" \
        12 "Aplicar Hardening de Segurança" \
        13 "Habilitar LDAPS (Certificado Autoassinado)" \
        "-" "------------------- INFRAESTRUTURA DE CERTIFICADOS ------------------" \
        14 "Criar Autoridade Certificadora (CA) Interna (gera wildcard)" \
        15 "Configurar LDAPS com Certificado" \
        16 "Distribuir Certificado CA para Clientes" \
        "-" "---------------------- GERENCIAMENTO DE GPOS ----------------------" \
        17 "Remover GPOs Padrão do Samba (Default Domain Policy)(opcional)" \
        18 "Criar GPOs de Hardening (lista predefinida)" \
        19 "Finalizar Segurança (restaurar full_audit + smb encrypt)" \
        "-" "------------------------ BACKUP E RESTORE -------------------------" \
        20 "Realizar Backup Manual do Samba AD DC" \
        21 "Restaurar de Backup (Desastre)" \
        "-" "-------------------------- UTILITÁRIOS ---------------------------" \
        22 "Verificar Instalação" \
        23 "Executar Implantação BÁSICA (1-8)" \
        24 "Executar Implantação AVANÇADA (9-13)" \
        25 "Sair")

    case $CHOICE in
        1)  bash "$SCRIPT_DIR/set_hostname.sh" ;;
        2)  bash "$SCRIPT_DIR/set_network.sh" ;;
        3)  bash "$SCRIPT_DIR/set_resolv.sh" ;;
        4)  bash "$SCRIPT_DIR/install_packages.sh" ;;
        5)  bash "$SCRIPT_DIR/configure_chrony.sh" ;;
        6)  bash "$SCRIPT_DIR/configure_kerberos.sh" ;;
        7)  bash "$SCRIPT_DIR/provision_domain.sh" ;;
        8)  bash "$SCRIPT_DIR/configure_services.sh" ;;
        9)  bash "$SCRIPT_DIR/raise_functional_level.sh" ;;
        10) bash "$SCRIPT_DIR/configure_dns_reverse.sh" ;;
        11) bash "$SCRIPT_DIR/configure_pso.sh" ;;
        12) bash "$SCRIPT_DIR/harden_samba.sh" ;;
        13) bash "$SCRIPT_DIR/enable_ldaps.sh" ;;
        14) bash "$SCRIPT_DIR/setup_ca.sh" ;;
        15) bash "$SCRIPT_DIR/configure_ldaps_with_wildcard.sh" ;;
        16) bash "$SCRIPT_DIR/distribute_ca.sh" ;;
        17) bash "$SCRIPT_DIR/remove_default_gpos.sh" ;;
        18) bash "$SCRIPT_DIR/create_hardening_gpos.sh" ;;
        19) bash "$SCRIPT_DIR/finalize_samba_security.sh" ;;
        20) bash "$SCRIPT_DIR/samba_backup.sh" ;;
        21) bash "$SCRIPT_DIR/samba_restore.sh" ;;
        22) bash "$SCRIPT_DIR/verify_installation.sh" ;;
        23)
            dialog --infobox "Executando etapas BÁSICAS..." 5 60
            sleep 1
            bash "$SCRIPT_DIR/set_hostname.sh" &&
            bash "$SCRIPT_DIR/set_network.sh" &&
            bash "$SCRIPT_DIR/set_resolv.sh" &&
            bash "$SCRIPT_DIR/install_packages.sh" &&
            bash "$SCRIPT_DIR/configure_chrony.sh" &&
            bash "$SCRIPT_DIR/configure_kerberos.sh" &&
            bash "$SCRIPT_DIR/provision_domain.sh" &&
            bash "$SCRIPT_DIR/configure_services.sh" &&
            info_box "✔ Implantação básica concluída com sucesso!"
            ;;
        24)
            dialog --infobox "Executando etapas AVANÇADAS..." 5 60
            sleep 1
            bash "$SCRIPT_DIR/raise_functional_level.sh" &&
            bash "$SCRIPT_DIR/configure_dns_reverse.sh" &&
            bash "$SCRIPT_DIR/configure_pso.sh" &&
            bash "$SCRIPT_DIR/harden_samba.sh" &&
            bash "$SCRIPT_DIR/enable_ldaps.sh" &&
            info_box "✔ Implantação avançada concluída com sucesso!"
            ;;
        25|"")
            clear
            echo
            echo "=============================================================="
            echo "   Encerrando Console de Implantação Samba AD DC            "
            echo "   @pedronels0n development                                  "
            echo "=============================================================="
            echo
            exit 0
            ;;
    esac
done