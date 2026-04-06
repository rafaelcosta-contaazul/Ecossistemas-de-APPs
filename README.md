# 🚀 Funil de Ativação de Apps: Documentação Técnica

Este repositório contém a inteligência de dados para análise dos ciclo dos desenvolvedores e aplicativos. O objetivo é monitorar a conversão desde o cadastro do desenvolvedor até o sucesso transacional com empresas reais (PME).

## 🧠 1. Visão Geral e Regras de Negócio

### 1.1 Objetivo do Funil
Consolidar a jornada completa do desenvolvedor, identificando gargalos técnicos e de negócio entre a criação do app e a primeira requisição válida em produção.

### 1.2 Premissas de Dados
* **Granularidade:** 1 linha por aplicativo (`id_aplicativo` / `client_id`).
* **Relacionamento:** Um desenvolvedor pode possuir múltiplos aplicativos (**1:N**), mas cada aplicativo pertence a um único desenvolvedor (**1:1**).
* **Tabela partida:** O ponto de entrada é a `public_consumer` (Desenvolvedores).

---

## 🏗️ 2. Arquitetura de Dados (Linhagem)

| Alias | Tabela Original | Papel no Funil |
| :--- | :--- | :--- |
| **cog** | `public_consumer` | Cadastro e perfil do desenvolvedor (Entidade Mãe). |
| **app** | `public_application` | Registro e configuração do aplicativo (Entidade de Granularidade). |
| **log** | `cognito.logs` | Eventos de autenticação e validação de e-mail PME. |
| **api** | `apigee_export_analytics` | Logs de tráfego bruto na API em Produção. |
| **use** | `ef_usuario` | Base do ERP para vínculo oficial com clientes reais. |

---

## 📋 3. Dicionário de Dados

### 📋 Dicionário de Dados (Campos da Query Final)

| Coluna | Regra de Negócio (Significado) | Lógica SQL (Cálculo) |
| :--- | :--- | :--- |
| **id_desenvolvedor** | Identificador único do desenvolvedor no portal. | Chave primária (id) da tabela public_consumer. |
| **dev_id_empresa** | ID da empresa vinculada à conta do desenvolvedor. | Coluna company_id da base de consumidores. |
| **dev_email** | E-mail de contato do desenvolvedor (exclui @contaazul.com). | Filtro NOT LIKE aplicado na CTE inicial. |
| **ts_conta_criada** | Data e hora em que o desenvolvedor se cadastrou no portal. | Timestamp original filtrado em D-1. |
| **status_email** | Indica se o desenvolvedor confirmou a validade do e-mail. | Valor bruto da coluna email_verification_status. |
| **preencheu_pag_intecao** | Define se o dev completou o perfil de intenção de uso. | Valor booleano da coluna has_complete_info. |
| **is_icp** | Define se o desenvolvedor é o Cliente Ideal (Exposição Pública). | CASE WHEN exposition_type = 'PUBLIC' THEN TRUE. |
| **id_aplicativo** | Identificador único do aplicativo criado. | Deduplicado via ROW_NUMBER para unicidade por ID. |
| **client_id** | Chave pública do app usada para autenticação e rastreio de logs. | Chave natural de ligação entre tabelas de log. |
| **nm_app** | Nome atribuído ao aplicativo pelo desenvolvedor. | String original da tabela public_application. |
| **ts_app_criado** | Data e hora de nascimento do aplicativo. | Timestamp da primeira criação registrada no banco. |
| **is_deleted** | Indica se o aplicativo foi deletado ou continua ativo. | Valor booleano de deleção lógica. |
| **app_environment** | Normalização do ambiente de execução do aplicativo. | COALESCE para PROD ou DEV. |
| **dt_primeira_tentativa** | Primeiro registro de atividade desse app no Cognito. | MIN(creation_date) da primeira linha (seq=1). |
| **status_primeira_tentativa** | Resposta do sistema na 1ª tentativa de login. | Valor da coluna event_response na linha cronológica 1. |
| **dt_sucesso_pass** | Data do primeiro status 'Pass' na história do app. | Window Function MIN(CASE WHEN ... = 'Pass'). |
| **status_sucesso_final** | Resultado consolidado da jornada de autenticação. | Valida se existiu algum 'Pass' no histórico. |
| **flag_conecta_pme** | Identifica se o app é usado por PME ou robôs de teste. | MAX(CASE) se e-mail não contém @devportal. |
| **ts_tent_primeira_req** | Primeiro "batimento cardíaco" do app na Apigee (Produção). | MIN(created_at) agrupado por client_id. |
| **total_requisicoes** | Volume total de chamadas que o app fez na API. | Contagem simples (COUNT(*)) de logs na Apigee. |
| **flag_tentou_requisicao** | Marca se o app interagiu com a API (mesmo com erro). | Flag fixa 1 se o client_id estiver na Apigee. |
| **ts_primeiro_sucesso_pme** | Data do primeiro sucesso real (Status 2xx) com PME. | MIN de data com Status 2xx e Join ERP. |
| **qtd_empresas_distintas** | Quantidade de PMEs diferentes atendidas pelo app. | COUNT(DISTINCT company_id) após filtros de PME. |
| **flag_conectou_pme_real** | Sucesso final: Conexão bem-sucedida de negócio. | Flag fixa 1 se atingiu todos os critérios PME/Sucesso. |
