git init
git add README.md FAIRGIG_AGENT_SPEC.md FRONTEND_SUMMARY.md .gitignore
git commit -m "docs: add initial project documentation"

git add package.json package-lock.json eslint.config.js docker-compose.yml start-microservices.ps1
git commit -m "chore: add root configuration and docker setup"

if (Test-Path "seed") {
    git add seed
    git commit -m "chore: add database seeding scripts"
}

if (Test-Path "services/auth") {
    git add services/auth
    git commit -m "feat(auth): implement authentication microservice"
}

if (Test-Path "services/analytics") {
    git add services/analytics
    git commit -m "feat(analytics): implement analytics microservice"
}

if (Test-Path "services/anomaly") {
    git add services/anomaly
    git commit -m "feat(anomaly): implement anomaly detection system"
}

if (Test-Path "services/certificate") {
    git add services/certificate
    git commit -m "feat(certificate): implement certificate generation service"
}

if (Test-Path "services/earnings") {
    git add services/earnings
    git commit -m "feat(earnings): implement log and analytics service"
}

if (Test-Path "services/grievance") {
    git add services/grievance
    git commit -m "feat(grievance): implement grievance handling service"
}

if (Test-Path "services") {
    git add services
    git commit -m "feat(services): implement shared utilities and api gateway"
}

if (Test-Path "frontend/package.json") {
    git add frontend/package.json frontend/package-lock.json frontend/index.html
    if (Test-Path "frontend/vite.config.js") { git add frontend/vite.config.js }
    if (Test-Path "frontend/eslint.config.js") { git add frontend/eslint.config.js }
    git commit -m "chore(frontend): setup vite react environment"
}

if (Test-Path "frontend/src/components") {
    git add frontend/src/components
    git commit -m "feat(frontend): build reusable UI components and charts"
}

if (Test-Path "frontend/src/pages") {
    git add frontend/src/pages
    git commit -m "feat(frontend): implement core application pages"
}

if (Test-Path "frontend/src/services") { git add frontend/src/services }
if (Test-Path "frontend/src/context") { git add frontend/src/context }
if (Test-Path "frontend/src/hooks") { git add frontend/src/hooks }
if (Test-Path "frontend/src/utils") { git add frontend/src/utils }
git commit -m "feat(frontend): add api integrations and state management"

git add frontend
git commit -m "feat(frontend): resolve final ui styling and assets"

git add .
git commit -m "chore: final project stabilization"

git branch -M main
git remote add origin https://github.com/ahmed-ali-waiz/FairGig.git
git push -u origin main
