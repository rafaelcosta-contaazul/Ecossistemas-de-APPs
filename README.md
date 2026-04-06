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

| Nome da Coluna | Regra de Negócio (O que significa) | Lógica SQL (Como é calculado) |
| :--- | :--- | :--- |
| **id_desenvolvedor** | ID único do dev no portal. | Chave primária (`id`) da `public_consumer`. |
| **dev_id_empresa** | ID da empresa vinculada ao dev. | `company_id` da base de consumidores. |
| **dev_email** | E-mail de contato do dev (Exclui CA). | Filtro `NOT LIKE '%@contaazul.com%'`. |
| **ts_conta_criada** | Data/hora do cadastro do dev. | Timestamp original filtrado em `D-1`. |
| **is_icp** | Define se o dev é Cliente Ideal (Exposição Pública). | `CASE WHEN exposition_type = 'PUBLIC'`. |
| **id_aplicativo** | Identificador único do app. | Deduplicado via `ROW_NUMBER` por ID. |
| **client_id** | Chave pública do app para logs. | Chave de Join entre as bases de eventos. |
| **nm_app** | Nome do aplicativo. | String original da `public_application`. |
| **ts_app_criado** | Data de nascimento do aplicativo. | Timestamp de criação original. |
| **app_environment** | Ambiente do aplicativo (PROD ou DEV). | `COALESCE` para normalizar `PRODUCTION`. |
| **dt_primeira_tentativa** | Primeiro sinal de vida no Cognito. | `MIN(creation_date)` da sequência 1. |
| **status_sucesso_final** | Status consolidado de autenticação. | Valida se existiu ao menos um 'Pass'. |
| **flag_conecta_pme** | Identifica se o app é PME ou Robô. | `MAX(CASE)` se e-mail não contém `@devportal`. |
| **ts_tent_primeira_req** | Primeiro hit na Apigee (Produção). | `MIN(created_at)` na Apigee. |
| **total_requisicoes** | Volume de chamadas feitas na API. | `COUNT(*)` bruto na tabela Apigee. |
| **flag_tentou_requisicao** | Registro de interação com a API. | Flag `1` se o app aparece na Apigee. |
| **ts_primeiro_sucesso_pme** | 1º sucesso real com PME validada. | `MIN` com Status 2xx e Join ERP. |
| **qtd_empresas_distintas** | Alcance de carteira (PMEs atendidas). | `COUNT(DISTINCT company_id)` com PME real. |
| **flag_conectou_pme_real** | Sucesso Final de Negócio (O Troféu). | Flag `1` se atingiu todos os critérios PME. |
--
