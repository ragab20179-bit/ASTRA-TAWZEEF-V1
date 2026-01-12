# Quick Start: Update EWOA Fire Drill Workflow

## Why This Update is Needed

The GitHub App integration used by Manus doesn't have the `workflows` permission required to update workflow files. Therefore, the workflow file must be updated manually.

## What This Update Does

The updated workflow adds authentication support to the EWOA fire drill, which will:
- ✅ Fix the 403 DENIED errors
- ✅ Allow k6 tests to successfully execute requests
- ✅ Generate accurate evidence bundles
- ✅ Automatically create NCR/CAPA reports on SLA violations

## Update Instructions

### Option 1: Via GitHub Web Interface (Recommended)

1. **Navigate to the workflow file:**
   - Go to: https://github.com/ragab20179-bit/ASTRA-TAWZEEF-V1
   - Click: `.github/workflows/ewoa_fire_drill.yml`

2. **Edit the file:**
   - Click the pencil icon (✏️) in the top right
   - Select all content (Ctrl+A or Cmd+A)
   - Delete the old content

3. **Paste the new content:**
   - Copy the entire content from the file below
   - Paste into the editor

4. **Commit the changes:**
   - Scroll to bottom
   - Commit message: `feat: Update EWOA fire drill workflow with authentication`
   - Select: "Commit directly to the main branch"
   - Click: "Commit changes"

### Option 2: Via Git Command Line

```bash
# 1. Navigate to your local repository
cd /path/to/ASTRA-TAWZEEF-V1

# 2. Pull the latest changes
git pull origin main

# 3. Copy the new workflow file
# (The file is already in your local repository at .github/workflows/ewoa_fire_drill.yml)

# 4. Commit and push
git add .github/workflows/ewoa_fire_drill.yml
git commit -m "feat: Update EWOA fire drill workflow with authentication"
git push origin main
```

## New Workflow File Content

```yaml
name: EWOA Fire Drill

on:
  workflow_dispatch:
  push:
    paths:
      - "services/**"
      - "shared/**"
      - "tests/ewoa/**"
      - ".github/workflows/ewoa_fire_drill.yml"

jobs:
  ewoa_fire_drill:
    runs-on: ubuntu-latest
    timeout-minutes: 30

    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies (k6, jq, docker-compose)
        run: |
          set -euo pipefail
          sudo apt-get update
          sudo apt-get install -y jq docker-compose dirmngr --install-recommends

          # Install k6 (official repo)
          sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install -y k6

      - name: Start ASTRA services
        run: |
          set -euo pipefail

          # Ephemeral CI key (no secrets needed, no long-lived keys in CI logs)
          export EWOA_FIRE_DRILL_KEY="$(openssl rand -hex 24)"
          echo "EWOA_FIRE_DRILL_KEY generated."
          echo "EWOA_FIRE_DRILL_KEY=$EWOA_FIRE_DRILL_KEY" >> $GITHUB_ENV

          docker-compose up -d --build

      - name: Wait for ASTRA Core health
        run: |
          set -euo pipefail
          echo "Waiting for ASTRA Core..."
          for i in $(seq 1 60); do
            if curl -fsS http://localhost:8000/health >/dev/null 2>&1; then
              echo "ASTRA Core is ready."
              break
            fi
            sleep 1
          done

      - name: Wait for Orchestrator health
        run: |
          set -euo pipefail
          echo "Waiting for Orchestrator..."
          for i in $(seq 1 60); do
            if curl -fsS http://localhost:8001/health >/dev/null 2>&1; then
              echo "Orchestrator is ready."
              break
            fi
            sleep 1
          done

      - name: Guardrail - Forbid unsupported k6 imports
        run: |
          set -euo pipefail
          if grep -RIn --exclude-dir=node_modules --exclude-dir=.git "Diff" ./tests/ewoa; then
            echo "ERROR: Found forbidden token 'Diff' in k6 scripts."
            exit 1
          fi
          echo "Guardrail passed. No 'Diff' token found."

      - name: Debug - Show baseline script content
        run: |
          set -euo pipefail
          echo "=== First 40 lines of baseline script ==="
          nl -ba ./tests/ewoa/01_k6_baseline.js | sed -n '1,40p'
          echo "========================================"

      - name: Run Baseline Test (host k6)
        env:
          BASE_URL: http://localhost:8001
          EWOA_FIRE_DRILL_KEY: ${{ env.EWOA_FIRE_DRILL_KEY }}
        run: |
          set -euo pipefail
          k6 run ./tests/ewoa/01_k6_baseline.js \
            --summary-export /tmp/k6-baseline-summary.json \
            2>&1 | tee /tmp/k6-baseline-output.txt

      - name: Run Overload Test (host k6)
        env:
          BASE_URL: http://localhost:8001
          EWOA_FIRE_DRILL_KEY: ${{ env.EWOA_FIRE_DRILL_KEY }}
        run: |
          set -euo pipefail
          k6 run ./tests/ewoa/02_k6_overload.js \
            --summary-export /tmp/k6-overload-summary.json \
            2>&1 | tee /tmp/k6-overload-output.txt

      - name: Collect EWOA evidence (always)
        if: always()
        run: |
          set -euo pipefail
          ./tests/ewoa/collect_evidence.sh /tmp/k6-baseline-summary.json /tmp/k6-overload-summary.json

      - name: Evaluate evidence and determine NCR requirement
        id: evaluate-evidence
        if: always()
        run: |
          set -euo pipefail
          
          # Check if evidence bundle was generated
          if [ ! -f /tmp/ewoa_evidence_bundle.json ]; then
            echo "ERROR: Evidence bundle not found"
            exit 1
          fi
          
          # Determine whether NCR is required
          RESULT=$(jq -r '.summary.result' /tmp/ewoa_evidence_bundle.json)
          
          if [ "$RESULT" = "FAIL" ]; then
            echo "Drill failed! NCR required."
            echo "ncr_required=true" >> "$GITHUB_OUTPUT"
          else
            echo "Drill passed. No NCR required."
            echo "ncr_required=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Generate NCR
        if: steps.evaluate-evidence.outputs.ncr_required == 'true'
        run: |
          set -euo pipefail
          echo "Generating NCR..."
          mkdir -p 09_Reports_and_Outputs/NCR_CAPA/$(date +%Y-%m-%d)
          TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
          NCR_ID="NCR_$(date +%s)"

          # Extract violation details from evidence bundle
          LATENCY_VIOLATED=$(jq -r '.summary.latency_violated' /tmp/ewoa_evidence_bundle.json)
          ERROR_VIOLATED=$(jq -r '.summary.error_violated' /tmp/ewoa_evidence_bundle.json)
          DENIAL_VIOLATED=$(jq -r '.summary.denial_violated' /tmp/ewoa_evidence_bundle.json)
          
          P95_LATENCY=$(jq -r '.signals[] | select(.signal_id=="exec_latency_p95") | .value' /tmp/ewoa_evidence_bundle.json)
          ERROR_RATE=$(jq -r '.signals[] | select(.signal_id=="http_fail_rate") | .value' /tmp/ewoa_evidence_bundle.json)
          DENIAL_RATE=$(jq -r '.signals[] | select(.signal_id=="denial_rate") | .value' /tmp/ewoa_evidence_bundle.json)

          cat > "09_Reports_and_Outputs/NCR_CAPA/$(date +%Y-%m-%d)/${NCR_ID}.md" << NCREOF
          # Non-Conformance Report (NCR)

          **NCR ID:** ${NCR_ID}  
          **Timestamp:** ${TIMESTAMP}  
          **Status:** OPEN  

          ## Violation Details
          
          ### SLA Violations Detected
          - **Latency SLA Violated:** ${LATENCY_VIOLATED}
          - **Error Rate SLA Violated:** ${ERROR_VIOLATED}
          - **Denial Rate SLA Violated:** ${DENIAL_VIOLATED}
          
          ### Actual Metrics
          - **P95 Latency:** ${P95_LATENCY}ms (Threshold: 100ms)
          - **Error Rate:** ${ERROR_RATE} (Threshold: 0.1)
          - **Denial Rate:** ${DENIAL_RATE} (Threshold: 0.05)
          
          ### Component
          - **System:** ASTRA/TAWZEEF Hot Path
          - **Service:** Execution Orchestrator

          ## Evidence
          - Evidence Bundle: /tmp/ewoa_evidence_bundle.json (this run)
          - Baseline Test Summary: /tmp/k6-baseline-summary.json
          - Overload Test Summary: /tmp/k6-overload-summary.json

          ## Actions Required
          1. Run performance analysis under load
          2. Identify bottleneck (DB insert, ASTRA decision latency, orchestration)
          3. Propose corrective action (Repair Plan Generator Phase 2)
          4. Re-run fire drill until PASS
          NCREOF

          echo "NCR generated: ${NCR_ID}.md"

      - name: Generate CAPA
        if: steps.evaluate-evidence.outputs.ncr_required == 'true'
        run: |
          set -euo pipefail
          echo "Generating CAPA..."
          mkdir -p 09_Reports_and_Outputs/NCR_CAPA/$(date +%Y-%m-%d)
          TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
          CAPA_ID="CAPA_$(date +%s)"

          cat > "09_Reports_and_Outputs/NCR_CAPA/$(date +%Y-%m-%d)/${CAPA_ID}.md" << CAPAEOF
          # Corrective & Preventive Action (CAPA)

          **CAPA ID:** ${CAPA_ID}  
          **Timestamp:** ${TIMESTAMP}  
          **Status:** OPEN  

          ## Root Cause (to be validated)
          Latency/availability violation detected during EWOA fire drill.

          ## Corrective Action
          1. Identify bottleneck in hot path
          2. Optimize (no retries, no async in gate path)
          3. Re-run fire drill until PASS

          ## Preventive Action
          1. Keep latency guardrails enforced in CI
          2. Schedule regular EWOA fire drills
          3. Track p95/p99 trends (EWOA)
          CAPAEOF

          echo "CAPA generated: ${CAPA_ID}.md"

      - name: Commit NCR/CAPA reports
        if: steps.evaluate-evidence.outputs.ncr_required == 'true'
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add 09_Reports_and_Outputs/NCR_CAPA/
          git commit -m "chore: Add NCR/CAPA reports from EWOA fire drill [skip ci]" || echo "No changes to commit"
          git push || echo "Push failed, continuing..."

      - name: Upload k6 summaries + evidence as workflow artifacts (debuggable)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ewoa-fire-drill-artifacts
          path: |
            /tmp/k6-baseline-summary.json
            /tmp/k6-overload-summary.json
            /tmp/k6-baseline-output.txt
            /tmp/k6-overload-output.txt
            /tmp/ewoa_evidence_bundle.json
          if-no-files-found: warn

      - name: Cleanup services
        if: always()
        run: |
          set -euo pipefail
          docker-compose down
```

## After Updating

1. **Trigger the workflow:**
   - Go to: Actions → EWOA Fire Drill → Run workflow
   - Or push a change to trigger automatically

2. **Monitor the run:**
   - Watch for 200 status codes (not 403)
   - Check that error rate is low
   - Verify evidence bundle is generated

3. **Review results:**
   - Download workflow artifacts
   - Check evidence bundle JSON
   - Review any NCR/CAPA reports generated

## What to Expect

### Before Update (Current State)
```
❌ STATUS=403
❌ http_req_failed: 100%
❌ errors: 100%
❌ All requests denied
```

### After Update (Expected State)
```
✅ STATUS=200
✅ http_req_failed: <10%
✅ errors: <10%
✅ execution_id present in responses
✅ Evidence bundle shows accurate metrics
```

## Troubleshooting

If you still see 403 errors after updating:

1. **Check workflow logs:**
   - Verify `EWOA_FIRE_DRILL_KEY generated.` message appears
   - Check that key is passed to k6 tests

2. **Check Docker logs:**
   ```bash
   docker-compose logs orchestrator | grep EWOA
   ```

3. **Verify k6 output:**
   - Look for `X-Fire-Drill-Key` in request headers
   - Check that status is 200, not 403

## Need Help?

If you encounter issues:
1. Check the comprehensive guide: `AUTHENTICATION_IMPLEMENTATION_SUMMARY.md`
2. Review the implementation guide: `pasted_content_39.txt`
3. Check GitHub Actions logs for detailed error messages

---

**Ready to update?** Choose Option 1 (Web Interface) or Option 2 (Command Line) above and follow the steps!
