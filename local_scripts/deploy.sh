#!/bin/bash
set -euo pipefail

##############################
# Funções Auxiliares
##############################
log_info() {
    echo "CICD [INFO]: $1"
}

log_error() {
    echo "CICD [ERRO]: $1" >&2
}

error_exit() {
    log_error "$1"
    exit 1
}

# Função para validar se um comando está instalado
check_command() {
    if ! command -v "$1" > /dev/null 2>&1; then
        error_exit "O comando '$1' não está instalado. Instale-o antes de executar este script."
    fi
}

##############################
# Validação dos Parâmetros de Entrada
##############################
if [ "$#" -lt 2 ]; then
    echo "Uso: $0 <profile> <env>"
    echo "Onde <env> pode ser 'dev' ou 'prd'"
    exit 1
fi

profile="$1"
env="$2"

if [ "$env" != "dev" ] && [ "$env" != "prd" ]; then
    error_exit "O parâmetro <env> deve ser 'dev' ou 'prd'. Valor informado: '$env'"
fi

##############################
# Validações Iniciais
##############################
check_command "aws"
check_command "terraform"
check_command "git"

# Valida se o perfil AWS existe
if ! aws configure list-profiles | grep -q "^${profile}\$"; then
    error_exit "O perfil AWS CLI '$profile' não foi encontrado. Configure-o antes de executar este script."
fi

##############################
# Configuração das Variáveis de Ambiente AWS
##############################
export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile "$profile")
export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile "$profile")
export AWS_SESSION_TOKEN=$(aws configure get aws_session_token --profile "$profile")
export AWS_DEFAULT_REGION=$(aws configure get region --profile "$profile")

log_info "Variáveis AWS configuradas para o perfil '$profile':"
log_info "  AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
log_info "  AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"

##############################
# Integração com o Git
##############################
# Garante que as branches 'dev' e 'master' existam; se não, cria-as e publica automaticamente
for branch in dev master; do
    if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
        log_info "A branch '${branch}' não existe. Criando-a..."
        git branch "${branch}"
        log_info "Publicando a branch '${branch}'..."
        git push -u origin "${branch}"
    fi
done

# Obtém o nome da branch atual
current_branch=$(git rev-parse --abbrev-ref HEAD)
log_info "Branch atual: $current_branch"

# Publica a branch atual se ainda não estiver no remoto
if ! git ls-remote --heads origin "$current_branch" > /dev/null 2>&1; then
    log_info "A branch '$current_branch' não está publicada no remoto. Publicando..."
    git push -u origin "$current_branch"
fi

# Configura o comportamento do pull para usar rebase
log_info "Configurando o comportamento do pull para usar rebase..."
git config pull.rebase true

##############################
# Operações de Merge e Rebase / Deploy
##############################
if [ "$env" == "dev" ]; then
    # Para deploy em dev, a branch atual pode ser 'dev'
    if [ "$current_branch" == "master" ]; then
        error_exit "Para deploy em DEV, a branch atual não pode ser 'master'."
    elif [ "$current_branch" == "dev" ]; then
        log_info "Deploy para ambiente DEV realizado a partir da branch 'dev'. Nenhum merge será realizado."
    else
        log_info "Fazendo merge da branch '$current_branch' na branch 'dev'..."
        git checkout dev
        git pull --rebase origin dev

        if ! git merge --ff-only "$current_branch"; then
            log_info "Fast-forward não possível. Realizando rebase da branch '$current_branch' sobre 'dev'..."
            git checkout "$current_branch"
            git rebase dev
            git checkout dev
            git merge --ff-only "$current_branch"
        fi

        if ! git push origin dev; then
            log_info "Push reprovado. Atualizando branch 'dev' e tentando novamente..."
            git pull --rebase origin dev
            git push origin dev
        fi

        log_info "Atualizando a branch '$current_branch' para sincronizar com 'dev'..."
        git checkout "$current_branch"
        git reset --hard dev
        git push origin "$current_branch" --force
    fi

elif [ "$env" == "prd" ]; then
    # Para deploy em prd, a branch atual deve ser 'dev'
    if [ "$current_branch" != "dev" ]; then
        error_exit "Para deploy em prd (master), a branch atual deve ser 'dev'."
    fi

    log_info "Fazendo merge da branch 'dev' na branch 'master'..."
    git checkout master
    git pull --rebase origin master

    log_info "Atualizando a branch 'dev' e rebaseando sobre 'master'..."
    git checkout dev
    git pull --rebase origin dev
    git rebase master

    log_info "Realizando merge fast-forward de 'dev' em 'master'..."
    git checkout master
    if ! git merge --ff-only dev; then
        error_exit "Fast-forward não possível mesmo após rebase."
    fi

    if ! git push origin master; then
        log_info "Push reprovado. Atualizando branch 'master' e tentando novamente..."
        git pull --rebase origin master
        git push origin master
    fi

    log_info "Atualizando a branch 'dev' para que fique igual à 'master'..."
    git checkout dev
    git reset --hard master
    git push origin dev --force
fi

##############################
# Deploy via Terraform com Cópia do Repositório
##############################
# Define a branch de deploy: para 'dev' usa-se 'dev' e para 'prd' usa-se 'master'
if [ "$env" == "dev" ]; then
    deploy_branch="dev"
else
    deploy_branch="master"
fi

# Obtém a URL do repositório remoto
repo_url=$(git remote get-url origin)
log_info "Obtendo cópia do repositório remoto (branch '$deploy_branch') a partir de: $repo_url"

# Cria um diretório temporário para clonar o repositório
temp_dir=$(mktemp -d)
# Garante a remoção do diretório temporário ao final da execução
trap 'rm -rf "$temp_dir"' EXIT

# Clona a branch de deploy no diretório temporário
git clone --branch "$deploy_branch" --single-branch "$repo_url" "$temp_dir" || error_exit "Falha ao clonar a branch '$deploy_branch' do repositório remoto."

log_info "Clone concluído. Executando Terraform no diretório temporário: $temp_dir/infra"

# Executa o Terraform a partir da cópia clonada
terraform -chdir="$temp_dir/infra" init -reconfigure -backend-config="env/${env}.backend.config" || error_exit "Terraform init falhou."
terraform -chdir="$temp_dir/infra" apply -auto-approve -var-file="env/${env}.tfvars" || error_exit "Terraform apply falhou."

log_info "Deploy via Terraform concluído com sucesso!"
