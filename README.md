# OS Management Gateway

Terraform-managed AWS API Gateway for the sibling `os-management` service.

The gateway exposes `ANY /{proxy+}` and forwards the request method, path,
query string, and body to the OS Management origin. For example, a request to
`https://<api-id>.execute-api.<region>.amazonaws.com/prod/clients` is proxied to
`http://<os-management-origin>:8080/clients`.

## GitHub secrets

Configure these repository secrets before running the workflow:

| Secret | Purpose |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | AWS credentials used by Terraform |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials used by Terraform |
| `AWS_REGION` | Region for the gateway, for example `us-east-1` |
| `OS_MANAGEMENT_ORIGIN_URL` | Base service URL, for example `http://<EC2-public-IP>:8080` |
| `TF_STATE_BUCKET` | Existing private S3 bucket that stores Terraform state |

The workflow runs on pushes to `main` and manually through **Run workflow**.
It reads every deployment value from GitHub Secrets; no credentials or origin
address are committed to the repository.

## Local use

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`, set
the values, then run:

```sh
cd terraform
terraform init
terraform apply
```

The S3 bucket in `TF_STATE_BUCKET` must already exist. The workflow enables
server-side encryption for the state object and uses a fixed gateway state key.
