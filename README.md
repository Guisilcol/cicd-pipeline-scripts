# CI/CD Pipeline Scripts

## Overview
Este repositório contém esteiras de CI/CD reutilizáveis para diversos projetos. Atualmente, armazena scripts para deploy local, permitindo que o desenvolvedor execute o deploy em sua própria máquina.

## Conteúdo
- Script de deploy local: `local_scripts/deploy.sh`
  - Realiza verificações pré-deploy, integração com Git e execução de Terraform para realizar o deploy.

## Pré-requisitos
Certifique-se de que os seguintes utilitários estejam instalados:
- [aws-cli](https://aws.amazon.com/cli/)
- [Terraform](https://www.terraform.io/downloads)
- [Git](https://git-scm.com/)

## Como Utilizar
1. Clone o repositório.
2. Configure o perfil AWS com os dados de acesso necessários (via arquivo de configuração ou variáveis de ambiente).
3. Execute o script de deploy, informando o perfil AWS e o ambiente desejado:
   ```
   ./local_scripts/deploy.sh <profile> <env>
   ```
   - Utilize `dev` para ambiente de desenvolvimento.
   - Utilize `prd` para ambiente de produção (o deploy será realizado na branch master).
4. O script irá:
   - Validar a instalação de dependências.
   - Verificar e configurar os perfis AWS.
   - Atualizar e gerenciar branches Git.
   - Realizar deploy via Terraform a partir de uma cópia clonada do repositório.

## Notas
- O script é denominado "local" porque deve ser executado na máquina do desenvolvedor.
- Verifique se todas as dependências (aws-cli, terraform, git) estão instaladas.
