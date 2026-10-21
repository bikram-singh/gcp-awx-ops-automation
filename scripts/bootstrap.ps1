param(
  [Parameter(Mandatory = $true)][string]$ProjectId,
  [Parameter(Mandatory = $true)][string]$GithubRepo,
  [string]$Region = "asia-south1",
  [string]$StateBucket = "$ProjectId-tfstate",
  [string]$PoolId = "github-pool",
  [string]$ProviderId = "github-provider",
  [string]$DeployerSaName = "tf-deployer"
)

$ErrorActionPreference = "Continue"

function Invoke-Gcloud {
  & gcloud @args
  if ($LASTEXITCODE -ne 0) { throw "gcloud failed: gcloud $($args -join ' ')" }
}

function Test-Gcloud {
  & gcloud @args *> $null
  return ($LASTEXITCODE -eq 0)
}

$DeployerSa = "$DeployerSaName@$ProjectId.iam.gserviceaccount.com"

Write-Host ">> Using project $ProjectId, repo $GithubRepo"
Invoke-Gcloud config set project $ProjectId
$ProjectNumber = "$(& gcloud projects describe $ProjectId '--format=value(projectNumber)')".Trim()
if (-not $ProjectNumber) { throw "Could not read the project number. Are you logged in (gcloud auth login)?" }

Write-Host ">> Enabling bootstrap APIs"
Invoke-Gcloud services enable iam.googleapis.com iamcredentials.googleapis.com cloudresourcemanager.googleapis.com serviceusage.googleapis.com sts.googleapis.com storage.googleapis.com

Write-Host ">> Creating Terraform state bucket gs://$StateBucket"
if (-not (Test-Gcloud storage buckets describe "gs://$StateBucket")) {
  Invoke-Gcloud storage buckets create "gs://$StateBucket" "--location=$Region" --uniform-bucket-level-access --public-access-prevention
}
Invoke-Gcloud storage buckets update "gs://$StateBucket" --versioning

Write-Host ">> Creating deployer service account $DeployerSa"
if (-not (Test-Gcloud iam service-accounts describe $DeployerSa)) {
  Invoke-Gcloud iam service-accounts create $DeployerSaName "--display-name=Terraform deployer GitHub Actions"
  Start-Sleep -Seconds 15
}

$roles = @(
  "roles/compute.admin",
  "roles/container.admin",
  "roles/cloudsql.admin",
  "roles/secretmanager.admin",
  "roles/iam.serviceAccountAdmin",
  "roles/iam.serviceAccountUser",
  "roles/resourcemanager.projectIamAdmin",
  "roles/servicenetworking.networksAdmin",
  "roles/serviceusage.serviceUsageAdmin",
  "roles/pubsub.admin",
  "roles/monitoring.admin",
  "roles/logging.admin"
)
foreach ($role in $roles) {
  Write-Host "   granting $role"
  Invoke-Gcloud projects add-iam-policy-binding $ProjectId "--member=serviceAccount:$DeployerSa" "--role=$role" --condition=None | Out-Null
}

Invoke-Gcloud storage buckets add-iam-policy-binding "gs://$StateBucket" "--member=serviceAccount:$DeployerSa" --role=roles/storage.objectAdmin | Out-Null

Write-Host ">> Creating Workload Identity pool and GitHub provider"
if (-not (Test-Gcloud iam workload-identity-pools describe $PoolId --location=global)) {
  Invoke-Gcloud iam workload-identity-pools create $PoolId --location=global "--display-name=GitHub Actions"
}

if (-not (Test-Gcloud iam workload-identity-pools providers describe $ProviderId --location=global "--workload-identity-pool=$PoolId")) {
  Invoke-Gcloud iam workload-identity-pools providers create-oidc $ProviderId `
    --location=global `
    "--workload-identity-pool=$PoolId" `
    "--display-name=GitHub OIDC" `
    "--issuer-uri=https://token.actions.githubusercontent.com" `
    "--attribute-mapping=google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" `
    "--attribute-condition=assertion.repository=='$GithubRepo'"
}

Write-Host ">> Allowing the repo to impersonate the deployer service account"
$member = "principalSet://iam.googleapis.com/projects/$ProjectNumber/locations/global/workloadIdentityPools/$PoolId/attribute.repository/$GithubRepo"
Invoke-Gcloud iam service-accounts add-iam-policy-binding $DeployerSa --role=roles/iam.workloadIdentityUser "--member=$member" | Out-Null

$WifProvider = "projects/$ProjectNumber/locations/global/workloadIdentityPools/$PoolId/providers/$ProviderId"

Write-Host ""
Write-Host "====================================================================="
Write-Host "Bootstrap complete. Add these as GitHub repository VARIABLES"
Write-Host "(Settings > Secrets and variables > Actions > Variables):"
Write-Host ""
Write-Host "  GCP_PROJECT_ID    = $ProjectId"
Write-Host "  GCP_WIF_PROVIDER  = $WifProvider"
Write-Host "  GCP_DEPLOYER_SA   = $DeployerSa"
Write-Host "  TF_STATE_BUCKET   = $StateBucket"
Write-Host ""
Write-Host 'Also create a GitHub Environment named "production" with required'
Write-Host "reviewers; the apply job waits for approval there."
Write-Host "====================================================================="
