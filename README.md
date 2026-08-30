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
- GitHub Actions — CI (`terraform fmt`/`validate`) and CD (`develop`→homolog, `main`→prod)

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
- Remember to add the **`soat-architecture`** user to this repository.
