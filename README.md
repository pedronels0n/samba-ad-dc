---

# Samba AD DC Automation Framework

![Platform](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-blue?style=for-the-badge)
![Automation](https://img.shields.io/badge/Automation-Bash-green?style=for-the-badge)
![Infrastructure](https://img.shields.io/badge/Infrastructure-Active%20Directory-critical?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-lightgrey?style=for-the-badge)

---

## Executive Summary

O **Samba AD DC Automation Framework** é um conjunto estruturado de scripts para provisionamento automatizado de um **Active Directory Domain Controller** utilizando o Samba em ambientes baseados em Debian e Ubuntu.

O projeto foi desenvolvido com foco em:

* 🔒 Segurança
* 📈 Padronização
* ⚙️ Repetibilidade
* 🧩 Modularidade
* 🏢 Adoção corporativa

---

## Table of Contents

* [1. Architecture Overview](#1-architecture-overview)
* [2. Technology Stack](#2-technology-stack)
* [3. System Requirements](#3-system-requirements)
* [4. Deployment Model](#4-deployment-model)
* [5. Project Structure](#5-project-structure)
* [6. Installation Procedure](#6-installation-procedure)
* [7. Validation & Compliance Checks](#7-validation--compliance-checks)
* [8. Security Considerations](#8-security-considerations)
* [9. Operational Guidelines](#9-operational-guidelines)
* [10. Troubleshooting Guide](#10-troubleshooting-guide)
* [11. Governance & Contribution Model](#11-governance--contribution-model)
* [12. License](#12-license)

---

# 1. Architecture Overview

O framework provisiona um:

* Active Directory Domain Controller
* DNS integrado
* Kerberos Authentication Service
* LDAP Directory Service

Componentes principais:

* Samba AD DC
* Internal DNS Backend
* Kerberos (MIT-compatible configuration)
* Systemd service orchestration

---

# 2. Technology Stack

| Component          | Technology                 |
| ------------------ | -------------------------- |
| Directory Services | Samba                      |
| Operating System   | Debian 10+ / Ubuntu 18.04+ |
| Authentication     | Kerberos                   |
| Service Manager    | systemd                    |
| Automation         | Bash                       |

---

# 3. System Requirements

### Minimum Requirements

* 2 vCPU
* 2GB RAM (4GB recomendado)
* 20GB de armazenamento
* IP estático configurado
* Hostname FQDN válido

Exemplo:

```
dc1.corp.local
```

### Network Requirements

* Porta 53 (DNS)
* Porta 88 (Kerberos)
* Porta 135 (RPC)
* Porta 389 (LDAP)
* Porta 445 (SMB)
* Porta 464 (Kerberos change/set password)

---

# 4. Deployment Model

O processo de provisionamento é dividido em estágios controlados:

1. Validação de ambiente
2. Instalação de dependências
3. Configuração de Kerberos
4. Provisionamento do domínio
5. Configuração de serviços
6. Testes automatizados

Fluxo controlado via:

```
setup-samba-dc.sh
```

---

# 5. Project Structure

```
samba-ad-dc/
│
├── common.sh
├── install_packages.sh
├── configure_kerberos.sh
├── provision_domain.sh
├── configure_services.sh
├── verify_installation.sh
└── setup-samba-dc.sh
```

### Script Responsibilities

| Script                 | Responsibility                       |
| ---------------------- | ------------------------------------ |
| common.sh              | Logging, validations, error handling |
| install_packages.sh    | Dependency installation              |
| configure_kerberos.sh  | Kerberos configuration               |
| provision_domain.sh    | Domain provisioning                  |
| configure_services.sh  | Service enablement                   |
| verify_installation.sh | Post-deployment validation           |
| setup-samba-dc.sh      | Orchestration layer                  |

---

# 6. Installation Procedure

## Step 1 – Clone Repository

```bash
git clone https://github.com/your-org/samba-ad-dc.git
cd samba-ad-dc
```

## Step 2 – Set Permissions

```bash
chmod +x *.sh
```

## Step 3 – Execute Deployment

```bash
sudo ./setup-samba-dc.sh
```

---

# 7. Validation & Compliance Checks

Após a execução:

### Service Validation

```bash
systemctl status samba-ad-dc
```

### DNS Validation

```bash
host -t SRV _ldap._tcp.corp.local
```

### Kerberos Validation

```bash
kinit Administrator
klist
```

### Automated Validation

```bash
./verify_installation.sh
```

---

# 8. Security Considerations

Este projeto assume hardening básico, mas recomenda-se:

* Firewall ativo (UFW ou iptables)
* Desativar serviços Samba legados (smbd/nmbd)
* Backup periódico de `/var/lib/samba`
* Restrição de acesso SSH
* Uso de senha forte para Administrator
* Monitoramento via syslog ou SIEM

⚠️ Nunca execute em servidor já membro de domínio.

---

# 9. Operational Guidelines

### Backup Strategy

* Backup completo do diretório:

```
/var/lib/samba
```

* Backup do:

```
/etc/samba
```

### Atualizações

Sempre teste upgrades em ambiente de homologação antes de produção.

---

# 10. Troubleshooting Guide

### Service Fails to Start

```
journalctl -xe
```

### DNS Not Resolving

Verifique:

```
cat /etc/resolv.conf
```

### Provisioning Failure

* Verifique IP fixo
* Confirme FQDN correto
* Pare serviços conflitantes:

```
systemctl stop smbd nmbd winbind
```

---

# 11. Governance & Contribution Model

Este projeto segue boas práticas de versionamento:

* Semantic Versioning
* Branch strategy (main / develop)
* Pull Request obrigatório
* Code review recomendado

### Contribution Workflow

1. Fork do repositório
2. Criar branch feature/*
3. Commit padronizado
4. Pull Request documentado

---

# 12. License

MIT License

Este projeto pode ser utilizado em ambientes corporativos, educacionais ou laboratoriais.

---

# Enterprise Readiness

✔ Repetível
✔ Modular
✔ Auditável
✔ Documentado
✔ Production-Ready

---

Se quiser, posso agora:

* 📊 Adicionar diagrama de arquitetura (ASCII ou imagem)
* 🏢 Criar versão com branding corporativo
* 🔐 Adicionar seção formal de compliance (LGPD / ISO 27001)
* 🚀 Criar README nível “empresa multinacional”
* 📁 Gerar também arquivos corporativos (CODEOWNERS, SECURITY.md, CONTRIBUTING.md)

Qual nível corporativo você quer agora?
