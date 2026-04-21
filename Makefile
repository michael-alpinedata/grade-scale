# --- Application Management ---

.PHONY: dev build test docker-build docker-push api-push api-rollout-dev api-rollout-prod clean nuke infra-destroy-dev infra-destroy-prod help

help:
	@echo "GradeScale Management Commands:"
	@echo "  make dev               - Start backend in dev mode"
	@echo "  make test              - Run unit and integration tests"
	@echo "  make api-push          - Build and push Docker image to GHCR"
	@echo "  make api-rollout-dev   - Force update of the Dev container on Azure"
	@echo "  make api-rollout-prod  - Force update of the Prod container on Azure"
	@echo "  make infra-setup-backend - Create Azure Storage for Terraform state"
	@echo "  make infra-apply-dev   - Apply Terraform changes to Dev"
	@echo "  make infra-apply-prod  - Apply Terraform changes to Prod"
	@echo "  make nuke              - DESTROY EVERYTHING (Infra + Local artifacts)"

dev:
	npm run dev

build:
	npm run build

test:
	npm run test

docker-build:
	docker build -t grade-scale .

docker-push:
	docker tag grade-scale:latest ghcr.io/$(GH_USER)/grade-scale:latest
	docker push ghcr.io/$(GH_USER)/grade-scale:latest

# Combined command for simplicity
api-login:
	@echo "Logging into GHCR..."
	@echo $(GH_PAT) | docker login ghcr.io -u $(GH_USER) --password-stdin

api-push: api-login docker-build docker-push

api-rollout-dev:
	az containerapp update --name aca-gradescale-api-dev --resource-group rg-gradescale-dev --image ghcr.io/$(GH_USER)/grade-scale:latest --revision-suffix rev$$(date +%s)

api-rollout-prod:
	az containerapp update --name aca-gradescale-api-prod --resource-group rg-gradescale-prod --image ghcr.io/$(GH_USER)/grade-scale:latest --revision-suffix rev$$(date +%s)

clean:
	@echo "🧹 Cleaning local artifacts..."
	rm -rf dist node_modules frontend/dist .terraform
	find . -name ".terraform" -type d -exec rm -rf {} +
	find . -name "terraform.tfstate*" -delete

# --- Infrastructure (Terraform) ---

# Extract variables from .env with fallback to system/CLI
GROQ_KEY := $(shell grep GROQ_API_KEY .env 2>/dev/null | cut -d '=' -f2- | tr -d '\" ' )
GH_USER  := $(shell grep GITHUB_USERNAME .env 2>/dev/null | cut -d '=' -f2- | tr -d '\" ' )
ifeq ($(GH_USER),)
  GH_USER := $(shell gh api user -q .login 2>/dev/null)
endif

GH_PAT   := $(shell grep GITHUB_PAT .env 2>/dev/null | cut -d '=' -f2- | tr -d '\" ' )
ifeq ($(GH_PAT),)
  GH_PAT := $(shell gh auth token 2>/dev/null)
endif

DB_PASS  := $(shell grep AZURE_DB_PASSWORD .env 2>/dev/null | cut -d '=' -f2- | tr -d '\" ' )

# --- Database Management (Azure Dev) ---
AZ_DB_HOST = $(shell cd infra/environments/dev && terraform output -raw database_host)
AZ_DB_USER = psqladmin
AZ_DB_NAME = gradescale_dev
AZ_DB_URL  = 'postgresql://$(AZ_DB_USER):$(DB_PASS)@$(AZ_DB_HOST):5432/$(AZ_DB_NAME)?sslmode=require'

db-migrate-dev:
	@echo "🚀 Migrating Azure Dev Database..."
	DATABASE_URL=$(AZ_DB_URL) DIRECT_URL=$(AZ_DB_URL) npx prisma migrate deploy

db-push-dev:
	@echo "📤 Pushing schema to Azure Dev Database..."
	DATABASE_URL=$(AZ_DB_URL) npx prisma db push

db-seed-dev:
	@echo "🌱 Seeding Azure Dev Database..."
	DATABASE_URL=$(AZ_DB_URL) npx prisma db seed

db-reset-dev:
	@echo "⚠️  WARNING: Resetting Azure Dev database..."
	DATABASE_URL=$(AZ_DB_URL) npx prisma db execute --stdin <<EOF
	TRUNCATE TABLE "CriterionEvaluation", "Evaluation", "Submission", "Criterion", "Rubric", "Question", "Subject" CASCADE;
	EOF
	DATABASE_URL=$(AZ_DB_URL) npx prisma db seed

# --- Terraform ---

TF_VARS = TF_VAR_groq_api_key="$(GROQ_KEY)" TF_VAR_github_username="$(GH_USER)" TF_VAR_github_pat="$(GH_PAT)" TF_VAR_db_password="$(DB_PASS)"

infra-setup-backend:
	@chmod +x infra/backend_setup/init_backend.sh
	@./infra/backend_setup/init_backend.sh

infra-init-dev:
	@cd infra/environments/dev && terraform init

infra-apply-dev:
	@echo "Applying Dev Infrastructure..."
	@cd infra/environments/dev && $(TF_VARS) terraform apply -auto-approve

infra-init-prod:
	@cd infra/environments/prod && terraform init

infra-apply-prod:
	@echo "Applying Prod Infrastructure..."
	@cd infra/environments/prod && $(TF_VARS) terraform apply -auto-approve

infra-destroy-dev:
	@echo "🔥 Destroying Dev Infrastructure..."
	@cd infra/environments/dev && $(TF_VARS) terraform destroy -auto-approve

infra-destroy-prod:
	@echo "🔥 Destroying Prod Infrastructure..."
	@cd infra/environments/prod && $(TF_VARS) terraform destroy -auto-approve

nuke: clean
	@echo "🔥 Brute-force destruction of Azure Resource Groups..."
	-az group delete --name rg-gradescale-dev --yes --no-wait
	-az group delete --name rg-gradescale-prod --yes --no-wait
	-az group delete --name rg-gradescale-tfstate --yes --no-wait
	@echo "☢️  AZURE RESOURCES DELETION TRIGGERED. Local artifacts cleaned. Ready for fresh install."

# --- FRONTEND DEPLOYMENT ---
front-push-dev:
	@echo "🏗️ Building Frontend..."
	@API_URL=$$(cd infra/environments/dev && terraform output -raw container_app_url); \
	cd frontend && npm install && VITE_API_BASE_URL=https://$$API_URL npm run build
	@echo "🚀 Deploying to Azure Static Web App..."
	@TOKEN=$$(cd infra/environments/dev && terraform output -raw frontend_deployment_token); \
	cd frontend && npx @azure/static-web-apps-cli deploy ./dist --deployment-token $$TOKEN --env production
