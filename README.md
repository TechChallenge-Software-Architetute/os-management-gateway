# os-management-gateway 

API Gateway da plataforma OS Management (FIAP SOAT — Tech Challenge Fase 3).

Provisiona um **AWS API Gateway (REST)** que é o ponto de entrada público da plataforma:

- **`POST /auth`** → forwarded to the **auth issuer Lambda** (public; issues a JWT from a CPF).
- **`POST /auth/login`** → forwarded to the **backend** (public; staff login by e-mail/senha,
  bypasses the authorizer just like `/auth`).
- **`ANY /{proxy+}`** → protected by a **JWT TOKEN authorizer** (the authorizer Lambda), then
  proxied to the backend application running on Kubernetes.

As funções Lambda em si vivem no repositório **`os-management-lambda`**. Este repositório as
endereça por **nome determinístico** (`<lambda_name_prefix>-issuer-<environment>` e
`<lambda_name_prefix>-authorizer-<environment>`) e monta o ARN de invocação a partir da conta e
da região — **não** lê o `terraform_remote_state` do outro repositório. Era essa leitura que
tornava o deploy do gateway dependente do deploy do Lambda; agora os dois aplicam em qualquer
ordem.

## Arquitetura

```mermaid
flowchart LR
    cliente([Cliente])

    subgraph GW["AWS API Gateway (REST) — este repositório"]
        auth_route["Recurso: POST /auth<br/>(público, sem authorizer)"]
        proxy_route["Recurso: ANY /{proxy+}<br/>(protegido por authorizer)"]
        stage["Stage (homolog/prod)<br/>Access logs JSON + X-Ray"]
    end

    subgraph LAMBDA["os-management-lambda (referenciado por nome)"]
        issuer["Lambda: Auth Issuer"]
        authz["Lambda: Token Authorizer"]
    end

    backend[["Backend os-management<br/>(Kubernetes)"]]

    cliente -- "POST /auth {cpf}" --> auth_route
    auth_route -- "integração AWS_PROXY" --> issuer
    issuer -- "JWT" --> cliente

    cliente -- "ANY /* Bearer JWT" --> proxy_route
    proxy_route -- "invoca antes de rotear" --> authz
    authz -- "Allow / Deny (cache 300s)" --> proxy_route
    proxy_route -- "integração HTTP_PROXY" --> backend

    auth_route --- stage
    proxy_route --- stage
```

POST /auth {cpf}                    -> API Gateway -> Issuer Lambda -> JWT (cliente)
POST /auth/login {email,senha}      -> API Gateway -> backend       -> JWT (staff)
ANY /* (Authorization: Bearer JWT)  -> API Gateway -> Authorizer Lambda (allow/deny)
                                                   -> backend (Kubernetes) if allowed
```
POST /auth {cpf}                    -> API Gateway -> Lambda Issuer -> JWT
ANY /* (Authorization: Bearer JWT)  -> API Gateway -> Lambda Authorizer (allow/deny)
                                                   -> backend (Kubernetes) se permitido
```

## Tecnologias

- AWS API Gateway (REST), AWS Lambda (referenciada), Terraform (`~> 5.0` AWS provider)
- Logs de acesso estruturados (JSON) no CloudWatch + tracing X-Ray no stage
- GitHub Actions — CI (`terraform fmt`/`validate`) e CD (push para `develop` ou `main`; o nome da branch é o ambiente)

## Referência da API (Swagger / Postman)

Não há um documento OpenAPI gerado para o próprio gateway — ele apenas adiciona `POST /auth`
e encaminha todo o resto para o backend. Use a collection da plataforma no repositório principal:

- **Bruno / Postman:** [`os-management` → `bruno/os-management-api`](https://github.com/TechChallenge-Software-Architetute/os-management/tree/develop/bruno/os-management-api)
  - [`01 - Auth / 03 - Login via CPF (Serverless)`](https://github.com/TechChallenge-Software-Architetute/os-management/tree/develop/bruno/os-management-api/01%20-%20Auth) → `POST {{gatewayUrl}}/auth`
  - `02 - Clients / 07 - My Orders`, `09/10 - Decide Order` → rotas protegidas via `{{gatewayUrl}}`
- **Swagger UI (backend):** `https://<backend>/swagger-ui/index.html`

Aponte `gatewayUrl` para o output `auth_endpoint` (removendo o `/auth` final para obter a base).

## Passos para Execução e Deploy

Pré-requisito: a URL da aplicação backend precisa estar acessível.

O stack do `os-management-lambda` **não** precisa ter rodado antes: os nomes das funções e os
ARNs de invocação são derivados de `lambda_name_prefix` + `environment`. Enquanto as funções não
existirem, as rotas que dependem delas respondem 5xx em runtime, mas o `apply` do gateway
conclui normalmente.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # preencha com valores reais

terraform init \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=gateway/develop/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform apply
```

Outputs principais: `auth_endpoint`, `invoke_url`.

## Configuração do CI/CD

**Variables** do repositório: `TF_STATE_BUCKET`, `AWS_REGION`.
(`TF_STATE_BUCKET` também pode ser fornecida como secret do repositório.)

**Secrets** do repositório: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `ORIGIN_URL`
(URL base da aplicação backend em Kubernetes).

Chave de state: este repositório usa `gateway/<env>/terraform.tfstate` e **não lê o state de
nenhum outro repositório**.

O workflow de CD não tem mais o passo que verificava `lambda/<env>/terraform.tfstate` e falhava
quando o arquivo não existia. Era a única dependência real entre deploys do sistema.

## Ordem de Deploy

```
k8s-terraform -> database -> os-management-lambda -> os-management-gateway -> app
```

Essa é a ordem **recomendada** para o sistema ficar funcional ponta a ponta, não uma
dependência de deploy: nenhum stack lê o state de outro, então cada um aplica isoladamente e em
qualquer ordem.

## Notes
- The `ANY /{proxy+}` route is guarded by the **JWT authorizer**, which accepts any token
  signed with the shared `JWT_SECRET` (client or staff); the **backend** then enforces roles.
  Staff log in via the public **`POST /auth/login`** on this gateway and call protected routes
  through `/{proxy+}` with their staff JWT. (The backend Swagger UI is still reached directly,
  as it is not exposed as a public gateway route.)
- Protected calls only succeed if **os-management** runs the CPF-token filter (grants
  `ROLE_CLIENT`, resolves the client by document). Deploy os-management
  `feature/cpf-auth-integration` or later.
- The authorizer keeps a 300s result cache; the authorizer Lambda returns a stage-wide Allow
  (`…/<stage>/*/*`) so caching does not break multi-route sessions.
- Access logs are JSON in CloudWatch (`/aws/apigateway/<api>-<env>/access`) with `requestId`
  for correlation with the Lambda logs.
- Remember to add the **`soat-architecture`** user to this repository.
