# 🚀 GitHub Setup & CI/CD Deployment Guide

This guide explains how to set up GitHub Actions for automated testing, building, and deployment of ASTRA / TAWZEEF.

---

## Table of Contents

1. [Repository Setup](#repository-setup)
2. [GitHub Secrets Configuration](#github-secrets-configuration)
3. [CI/CD Workflows](#cicd-workflows)
4. [Deployment Process](#deployment-process)
5. [Monitoring Deployments](#monitoring-deployments)
6. [Troubleshooting](#troubleshooting)

---

## Repository Setup

### Step 1: Create GitHub Repository

```bash
# Initialize git in project directory
cd astra_taw_prod_v1
git init

# Add remote repository
git remote add origin https://github.com/YOUR_ORG/astra-tawzeef.git

# Create initial commit
git add .
git commit -m "Initial commit: ASTRA/TAWZEEF v1 with real authorization engine"

# Push to GitHub
git branch -M main
git push -u origin main
```

### Step 2: Repository Settings

1. Go to **Settings** → **General**
   - Enable "Require status checks to pass before merging"
   - Enable "Require branches to be up to date before merging"

2. Go to **Settings** → **Branches**
   - Set `main` as default branch
   - Add branch protection rule:
     - Require pull request reviews: 1
     - Require status checks: ci-guardrails, test, build

3. Go to **Settings** → **Actions**
   - Allow all actions and reusable workflows

---

## GitHub Secrets Configuration

### Step 1: Generate Deployment Key

```bash
# Generate SSH key pair
ssh-keygen -t ed25519 -f deploy_key -N ""

# Copy public key to deployment server
ssh-copy-id -i deploy_key.pub deploy_user@your-server.com

# Keep private key secure
cat deploy_key  # Copy this value
```

### Step 2: Add Secrets to GitHub

Go to **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add the following secrets:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `DEPLOY_KEY` | (paste private key) | SSH private key for deployment |
| `DEPLOY_HOST` | `your-server.com` | Production server hostname/IP |
| `DEPLOY_USER` | `deploy` | SSH user on deployment server |
| `DEPLOY_PATH` | `/opt/astra_taw_prod_v1` | Project path on server |
| `DOCKER_USERNAME` | (optional) | Docker Hub username |
| `DOCKER_PASSWORD` | (optional) | Docker Hub token |

### Step 3: Verify Secrets

```bash
# Test SSH connection
ssh -i deploy_key deploy_user@your-server.com "echo 'Connection successful'"
```

---

## CI/CD Workflows

### Workflow Files

The project includes two CI/CD workflows:

#### 1. **ci.yml** (Guardrails)
- Runs on: Every push and pull request
- Checks:
  - No forbidden constructs (async, retry, threading)
  - Docker image builds
- Status: Required for merge

#### 2. **deploy.yml** (Full CI/CD)
- Runs on: Push to main/production, manual trigger
- Steps:
  1. **Test & Validate**
     - Python syntax validation
     - JSON validation
     - SQL schema validation
     - Guardrails check
     - Decision engine logic tests
  2. **Build Docker Images**
     - Build ASTRA Core image
     - Build Orchestrator image
     - Build Watcher image
     - Push to GitHub Container Registry
  3. **Deploy to Production**
     - SSH to deployment server
     - Pull latest code
     - Pull latest images
     - Start services
     - Verify deployment

---

## Deployment Process

### Automatic Deployment (Main Branch)

```bash
# 1. Create feature branch
git checkout -b feature/your-feature

# 2. Make changes
# ... edit files ...

# 3. Commit and push
git add .
git commit -m "Add your changes"
git push origin feature/your-feature

# 4. Create Pull Request on GitHub
# - Go to GitHub
# - Click "Compare & pull request"
# - Add description
# - Request review

# 5. After approval, merge to main
# - GitHub Actions automatically:
#   - Runs tests
#   - Builds images
#   - Deploys to production
```

### Manual Deployment

Go to **Actions** → **Deploy to Production** → **Run workflow**

Select environment:
- `staging` — Test environment
- `production` — Production environment

---

## Monitoring Deployments

### View Workflow Status

1. Go to **Actions** tab
2. Click on workflow run
3. View step-by-step execution

### View Logs

```bash
# View workflow logs
# In GitHub Actions UI:
# Actions → [Workflow Name] → [Run] → [Job] → [Step]

# Or via GitHub CLI
gh run view [run-id] --log
```

### Deployment Notifications

Deployments are tracked in:
- **GitHub Actions** tab (real-time)
- **Deployments** tab (deployment history)
- **Pull Request** comments (deployment status)

---

## Workflow Configuration

### Environment Variables

Edit `.github/workflows/deploy.yml` to customize:

```yaml
env:
  REGISTRY: ghcr.io  # Change to docker.io for Docker Hub
  IMAGE_NAME: ${{ github.repository }}
```

### Trigger Conditions

Modify workflow triggers:

```yaml
on:
  push:
    branches:
      - main
      - production
      - develop  # Add other branches
  pull_request:
    branches:
      - main
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
```

### Deployment Environments

Add deployment environments in **Settings** → **Environments**:

1. **staging**
   - Deployment branch: `develop`
   - Required reviewers: Optional
   - Deployment branches: All branches

2. **production**
   - Deployment branch: `main`
   - Required reviewers: 1 (recommended)
   - Deployment branches: Protected branches only

---

## Best Practices

### Branch Strategy

```
main (production)
  ↑
  └─ pull request (reviewed)
       ↑
       └─ feature branch (your changes)
```

### Commit Messages

```bash
# Good commit messages
git commit -m "feat: add new authorization rule for interview domain"
git commit -m "fix: correct policy pack validation logic"
git commit -m "docs: update deployment guide"
git commit -m "refactor: simplify decision engine"

# Avoid
git commit -m "update"
git commit -m "fix bug"
```

### Pull Request Process

1. Create feature branch from `main`
2. Make changes and commit
3. Push to GitHub
4. Create Pull Request
5. Wait for CI/CD checks to pass
6. Request review from team
7. Address review comments
8. Merge after approval
9. GitHub Actions automatically deploys

---

## Troubleshooting

### Workflow Fails: Python Syntax Error

```
Error: SyntaxError in services/astra_core/main.py
```

**Solution:**
```bash
# Fix locally
python -m py_compile services/astra_core/main.py

# Commit fix
git add .
git commit -m "fix: correct syntax error"
git push origin feature/your-feature
```

### Workflow Fails: Docker Build Error

```
Error: failed to build image
```

**Solution:**
```bash
# Build locally to debug
docker compose build astra-core

# Check Dockerfile
cat services/astra_core/Dockerfile

# Fix and commit
git add .
git commit -m "fix: correct Dockerfile"
git push
```

### Workflow Fails: Deployment Connection Error

```
Error: ssh: connect to host failed
```

**Solution:**
1. Verify `DEPLOY_HOST` secret is correct
2. Verify `DEPLOY_KEY` secret is valid
3. Test SSH connection manually:
   ```bash
   ssh -i deploy_key deploy_user@your-server.com
   ```
4. Update secrets if needed

### Workflow Fails: Health Check Fails

```
Error: curl: (7) Failed to connect
```

**Solution:**
1. Check deployment server logs:
   ```bash
   ssh deploy_user@your-server.com
   cd /opt/astra_taw_prod_v1
   docker compose logs
   ```
2. Verify services are running:
   ```bash
   docker compose ps
   ```
3. Check firewall rules

---

## Advanced Configuration

### Custom Docker Registry

To push to Docker Hub instead of GitHub Container Registry:

```yaml
# In .github/workflows/deploy.yml
- name: Log in to Docker Hub
  uses: docker/login-action@v2
  with:
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_PASSWORD }}

- name: Build and push ASTRA Core
  uses: docker/build-push-action@v4
  with:
    context: .
    file: ./services/astra_core/Dockerfile
    push: true
    tags: ${{ secrets.DOCKER_USERNAME }}/astra-core:${{ github.sha }}
```

### Slack Notifications

Add Slack notifications on deployment:

```yaml
- name: Notify Slack
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    text: 'Deployment to production: ${{ job.status }}'
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

### Scheduled Deployments

Deploy on a schedule:

```yaml
on:
  schedule:
    - cron: '0 2 * * 0'  # Every Sunday at 2 AM UTC
```

---

## Security Best Practices

1. **Protect Main Branch**
   - Require pull request reviews
   - Require status checks to pass
   - Dismiss stale reviews

2. **Rotate Secrets Regularly**
   - SSH keys: Every 90 days
   - Docker tokens: Every 180 days

3. **Audit Deployments**
   - Review deployment logs
   - Monitor GitHub Actions usage
   - Check deployment history

4. **Limit Access**
   - Only required team members can approve deployments
   - Use environment protection rules
   - Enable audit logs

---

## Useful GitHub CLI Commands

```bash
# View workflow runs
gh run list --workflow=deploy.yml

# View specific run
gh run view [run-id]

# View run logs
gh run view [run-id] --log

# Cancel run
gh run cancel [run-id]

# View deployment history
gh deployment list --repo owner/repo

# View deployment status
gh deployment status [deployment-id]
```

---

## Support & Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub Secrets Documentation](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Docker GitHub Action](https://github.com/docker/build-push-action)
- [GitHub CLI Documentation](https://cli.github.com/)

---

## Next Steps

1. ✅ Create GitHub repository
2. ✅ Configure secrets
3. ✅ Push code to main branch
4. ✅ Verify workflows run
5. ✅ Monitor first deployment
6. ✅ Set up notifications (optional)

---

**Your ASTRA / TAWZEEF system is now ready for automated CI/CD deployment via GitHub Actions!**

