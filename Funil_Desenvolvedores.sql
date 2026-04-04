WITH 
-- ============================================================================
-- CTE 1: Base Mãe (Desenvolvedores)
-- ============================================================================
base_desenvolvedores AS (
    SELECT 
        id AS id_desenvolvedor,
        company_id AS id_empresa,
        email AS dev_email,
        Cast(created_at as Date) AS ts_conta_criada,
        email_verification_status AS status_email,
        has_complete_info AS preencheu_pag_intecao,
        CASE WHEN exposition_type = 'PUBLIC' THEN TRUE ELSE FALSE END AS is_icp 
    FROM `contaazul-ssbi.bronze_db_developers_portal.public_consumer`   
    WHERE email NOT LIKE '%@contaazul.com%'
      AND CAST(created_at AS DATE) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
),

-- ============================================================================
-- CTE 2: Granularidade Principal (Aplicativos)
-- ============================================================================
base_app_ranqueada AS (
    SELECT 
        id AS id_aplicativo, 
        client_id,
        consumer_id,
        app_name AS nm_app,
        Cast(created_at as Date) AS ts_app_criado,
        is_deleted,
        CASE WHEN COALESCE(environment, 'DEV') = 'PRODUCTION' THEN 'PROD' ELSE 'DEV' END AS app_environment,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at ASC) AS ranking
    FROM `contaazul-ssbi.bronze_db_developers_portal.public_application`
    WHERE CAST(created_at AS DATE) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
),
base_app AS (
    SELECT * EXCEPT(ranking) 
    FROM base_app_ranqueada 
    WHERE ranking = 1
),

-- ============================================================================
-- CTE 3: Tentativas de Log (Cognito)
-- ============================================================================
ranking_tentativas AS (
    SELECT 
        client_id,
        user_name,
        creation_date,
        event_response,
        ROW_NUMBER() OVER (PARTITION BY client_id ORDER BY creation_date ASC) AS seq,
        MIN(CASE WHEN event_response = 'Pass' THEN creation_date END) OVER (PARTITION BY client_id) AS data_primeiro_pass,
        MAX(CASE WHEN user_name NOT LIKE '%@devportal%' THEN 1 ELSE 0 END) OVER (PARTITION BY client_id) AS flag_tentativa_conexao_pme
    FROM `contaazul-ssbi.bronze_tool_cognito.logs`
),
tentativa_log AS (
    SELECT
        client_id,
        Cast(creation_date as Date) AS dt_primeira_tentativa_log,
        event_response AS status_primeira_tentativa_log,
        Cast(data_primeiro_pass as Date) AS dt_sucesso_pass,
        CASE WHEN data_primeiro_pass IS NOT NULL THEN 'Pass' ELSE 'Não Conectou' END AS status_sucesso_final,
        flag_tentativa_conexao_pme
    FROM ranking_tentativas
    WHERE seq = 1 
      AND CAST(creation_date AS DATE) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
),

-- ============================================================================
-- CTE 4: Tentativa de Requisição (Apigee Geral)
-- ============================================================================
tentativa_apigee AS (
    SELECT 
        client_id, 
        MIN(Cast(created_at as Date)) AS ts_tent_primeira_requisicao,
        COUNT(*) AS total_requisicoes,
        1 AS flag_tentativa_requisicao
    FROM `contaazul-ssbi.silver_master_data.apigee_export_analytics`
    WHERE CAST(created_at AS DATE) <= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    GROUP BY 1
),

-- ============================================================================
-- CTE 5: Conexão PME Real (Apigee + Usuários)
-- ============================================================================
pme_validas AS (
    SELECT DISTINCT u.id_empresa
    FROM `contaazul-ssbi.bronze_db_contaazul.public_ef_usuario` AS u
    INNER JOIN `contaazul-ssbi.bronze_tool_cognito.logs` AS c 
        ON u.ds_login = c.user_name
    WHERE c.user_name NOT LIKE '%@devportal%'
),
logs_resumidos AS (
    SELECT 
        client_id,
        company_id,
        MIN(CAST(created_at AS DATE)) AS ts_primeiro_sucesso_pme
    FROM `contaazul-ssbi.silver_master_data.apigee_export_analytics`
    WHERE target_response_code BETWEEN 200 AND 299
      AND created_at >= '2026-01-01'
    GROUP BY 1, 2
),
apigee_pme_real AS (
    SELECT 
        log.client_id,
        MIN(log.ts_primeiro_sucesso_pme) AS ts_primeiro_sucesso_pme,
        COUNT(DISTINCT log.company_id) AS qtd_empresas_distintas,
        1 AS flag_conectou_pme_real
    FROM logs_resumidos AS log
    INNER JOIN pme_validas AS pme 
        ON CAST(log.company_id AS STRING) = CAST(pme.id_empresa AS STRING) -- CAST para garantir o match do Join
    GROUP BY 1
)

-- ============================================================================
-- SELEÇÃO FINAL: CONSOLIDAÇÃO DO FUNIL
-- ============================================================================
SELECT 
    -- 1. Dados da Mãe (Desenvolvedor)
    dev.id_desenvolvedor,
    --dev.id_empresa AS dev_id_empresa,
    --dev.dev_email,
    dev.ts_conta_criada,
    dev.status_email,
    dev.preencheu_pag_intecao,
    dev.is_icp,

    -- 2. Granularidade (Aplicativo)
    --app.id_aplicativo,
    app.client_id,
    app.nm_app,
    app.ts_app_criado,
    app.is_deleted,
    app.app_environment,

    -- 3. Etapa Cognito (Tentativas)
    cog.dt_primeira_tentativa_log,
    cog.status_primeira_tentativa_log,
    cog.dt_sucesso_pass,
    cog.status_sucesso_final,
    cog.flag_tentativa_conexao_pme,

    -- 4. Etapa Apigee (Qualquer Requisição)
    api.ts_tent_primeira_requisicao,
    api.total_requisicoes,
    api.flag_tentativa_requisicao,

    -- 5. Etapa Apigee (PME Real Sucesso)
    pme.ts_primeiro_sucesso_pme,
    pme.qtd_empresas_distintas,
    pme.flag_conectou_pme_real

FROM base_desenvolvedores AS dev
INNER JOIN base_app AS app 
    ON dev.id_desenvolvedor = app.consumer_id
LEFT JOIN tentativa_log AS cog 
    ON app.client_id = cog.client_id
LEFT JOIN tentativa_apigee AS api 
    ON app.client_id = api.client_id
LEFT JOIN apigee_pme_real AS pme 
    ON app.client_id = pme.client_id;
