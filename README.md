# os-management-gateway

API Gateway for the os-management platform (FIAP SOAT — Tech Challenge Fase 3).

Provisions an **AWS API Gateway (REST)** that is the public entry point for the platform:

- **`POST /auth`** → forwarded to the **auth issuer Lambda** (public; issues a JWT from a CPF).
- **`ANY /{proxy+}`** → protected by a **JWT TOKEN authorizer** (the authorizer Lambda), then
  proxied to the backend application running on Kubernetes.

The Lambda functions themselves live in **`os-management-lambda`**; this repo reads their
invoke ARNs via `terraform_remote_state` and wires the gateway around them.

## Request flow

```
POST /auth {cpf}                    -> API Gateway -> Issuer Lambda -> JWT
ANY /* (Authorization: Bearer JWT)  -> API Gateway -> Authorizer Lambda (allow/deny)
                                                   -> backend (Kubernetes) if allowed
```

## Technologies
- AWS API Gateway (REST), AWS Lambda (referenced), Terraform (`~> 5.0` AWS provider)
- CloudWatch structured (JSON) access logs + X-Ray tracing on the stage
- GitHub Actions — CI (`terraform fmt`/`validate`) and CD (`develop`→homolog, `main`→prod)

## API reference (Swagger / Postman)

There is no OpenAPI document generated for the gateway itself — it only adds `POST /auth`
and forwards everything else to the backend. Use the platform collection in the main repo:

- **Bruno / Postman:** `os-management` → `bruno/os-management-api`
  - `01 - Auth / 03 - Login via CPF (Serverless)` → `POST {{gatewayUrl}}/auth`
  - `02 - Clients / 07 - My Orders`, `09/10 - Decide Order` → protected routes via `{{gatewayUrl}}`
- **Swagger UI (backend):** `https://<backend>/swagger-ui/index.html`

Point `gatewayUrl` at the `auth_endpoint` output (drop the trailing `/auth` for the base).

## Deploy

Prerequisites: the `os-management-lambda` stack must be applied first (its state provides
the functions' invoke ARNs), and the backend app URL must be reachable.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in real values

terraform init \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=gateway/homolog/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform apply
```

Key outputs: `auth_endpoint`, `invoke_url`.

## CI/CD configuration

Repo **variables**: `TF_STATE_BUCKET`, `AWS_REGION`.

Repo **secrets**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `ORIGIN_URL`
(base URL of the backend app on Kubernetes).

State keys (same bucket, distinct keys): this repo uses `gateway/<env>/terraform.tfstate`
and reads `lambda/<env>/terraform.tfstate`.

## Deploy order

```
k8s-terraform -> database -> os-management-lambda -> os-management-gateway -> app
```

## Notes
- The `ANY /{proxy+}` route is guarded by the **CPF JWT authorizer**, so it is the entry
  point for **clients**. Staff (ADMIN/TECHNICIAN) authenticate with e-mail/password directly
  against the backend `POST /auth/login` and the backend Swagger UI is reached directly — not
  through this gateway.
- Protected calls only succeed if **os-management** runs the CPF-token filter (grants
  `ROLE_CLIENT`, resolves the client by document). Deploy os-management
  `feature/cpf-auth-integration` or later.
- The authorizer keeps a 300s result cache; the authorizer Lambda returns a stage-wide Allow
  (`…/<stage>/*/*`) so caching does not break multi-route sessions.
- Access logs are JSON in CloudWatch (`/aws/apigateway/<api>-<env>/access`) with `requestId`
  for correlation with the Lambda logs.
- Remember to add the **`soat-architecture`** user to this repository.
