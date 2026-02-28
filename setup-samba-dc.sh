#!/bin/bash
# ==========================================================
#  Samba AD DC Automation Framework
#  Console Interativo de Implantação
#  @pedronels0n development
#  Versão: 1.0.0
# ==========================================================

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/common.sh"

check_root
check_dialog

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
        --backtitle "Samba AD DC Automation Framework v1.0.0 | @pedronels0n development" \
        --title "Menu Principal" \
        --menu "Selecione uma opção:" 27 95 18 \
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
        13 "Habilitar LDAPS (Certificado TLS)" \
        "-" "-------------------------- UTILITÁRIOS ---------------------------" \
        14 "Verificar Instalação" \
        15 "Executar Implantação BÁSICA (1-8)" \
        16 "Executar Implantação AVANÇADA (9-13)" \
        17 "Sair")

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
        14) bash "$SCRIPT_DIR/verify_installation.sh" ;;

        15)
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
        16)
            dialog --infobox "Executando etapas AVANÇADAS..." 5 60
            sleep 1
            bash "$SCRIPT_DIR/raise_functional_level.sh" &&
            bash "$SCRIPT_DIR/configure_dns_reverse.sh" &&
            bash "$SCRIPT_DIR/configure_pso.sh" &&
            bash "$SCRIPT_DIR/harden_samba.sh" &&
            bash "$SCRIPT_DIR/enable_ldaps.sh" &&
            info_box "✔ Implantação avançada concluída com sucesso!"
            ;;
        17|"")
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