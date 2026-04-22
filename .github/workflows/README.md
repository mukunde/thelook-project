# GitHub Actions Workflows

| Workflow | File | Trigger |
|---|---|---|
| Python CI | `python-ci.yml` | Push / PR on `*.py`, `pyproject.toml`, `uv.lock` |
| Terraform CI | `terraform-ci.yml` | Push / PR on `infra/terraform/**` |

## python-ci.yml

Runs on every Python change:
1. **ruff check** — lint
2. **ruff format --check** — formatting
3. **mypy** — static type checking (continue-on-error while scaffolding)
4. **pytest** — unit tests (continue-on-error while scaffolding)

## terraform-ci.yml

Runs in matrix `[snowflake, oci]` on every Terraform change:
1. **terraform fmt -check** — formatting guard
2. **terraform init -backend=false** — provider resolution without remote state
3. **terraform validate** — schema + logic validation
4. **tflint --init && tflint --recursive** — linting via `.tflint.hcl`
