#!/bin/bash

SCRIPT_TITLE="Helm Chart Validation Script"

set -Eeuo pipefail

# Function to handle errors.
function on_error {
  echo ""
  echo "❌ An error occurred on line ${LINENO}." >&2
  echo "Exiting with status 1." >&2
  exit 1
}
trap on_error ERR

# --- Start of the main script logic ---

echo "=============================================="
echo "🚀 ${SCRIPT_TITLE}"
echo "=============================================="
echo ""
# 1. Basic Chart Syntax and Structure Validation
# This is the first and fastest check. 'helm lint' validates the chart's structure and YAML files against Helm's best practices.
echo ""
echo "--- Step 1: Validating chart syntax with 'helm lint' ---"
# Define an array of Helm charts to validate.
declare -a CHARTS=("api-gateway" "product-service" "user-service")
CHARTS_DIR="../charts"

# Validate that the charts directory exists before proceeding.
# defensive check.
if [[ ! -d "${CHARTS_DIR}" ]]; then
  echo "❌ Error: Charts directory '${CHARTS_DIR}' not found. Please ensure the path is correct."
  exit 1
fi

# Use a loop to iterate through each chart and perform validation.
for chart in "${CHARTS[@]}"; do
  CHART_PATH="${CHARTS_DIR}/${chart}"

  if [[ ! -d "${CHART_PATH}" ]]; then
    echo "❌ Error: Chart directory '${CHART_PATH}' not found. Skipping validation for this chart."
    continue
  fi

  echo "Validating chart: ${chart}..."
  
  # Run `helm lint` to check for syntax and best practices.
  # Redirect the output to make the script less noisy on success.
  if helm lint "${CHART_PATH}" >/dev/null; then
    echo "✅ Linting successful."
  else
    echo "❌ Linting failed for ${chart}. Please check the chart for errors."
    exit 1
  fi
  
  if helm template "test-${chart}" "${CHART_PATH}" >/dev/null; then
    echo "✅ Template validation successful."
  else
    echo "❌ Template validation failed for ${chart}. Please check the chart's templates."
    exit 1
  fi

  echo "----------------------------------------------"
done

# 2. Chart.yaml File Verification
# This check ensures that the metadata in Chart.yaml is valid and can be read by Helm.
echo ""
echo "--- Step 2: Verifying Chart.yaml files ---"
for chart in "${CHARTS[@]}"; do
  CHART_PATH="${CHARTS_DIR}/${chart}/"
  echo "📄 Checking Chart.yaml for ${chart}..."
  helm show chart "${CHART_PATH}" >/dev/null
  echo "✅ Chart.yaml is valid for ${chart}."
done

# 3. Template Rendering and Syntax Validation
# This step checks that the templates can be rendered into valid Kubernetes YAML.
# The 'helm template' command is perfect for this, as it doesn't require a cluster connection.
echo ""
echo "--- Step 3: Validating template rendering ---"
for chart in "${CHARTS[@]}"; do
  CHART_PATH="${CHARTS_DIR}/${chart}/"
  echo "📝 Rendering templates for ${chart}..."
  helm template "${chart}" "${CHART_PATH}" >/dev/null
  echo "✅ Templates are valid for ${chart}."
done

# 4. Comprehensive Dry Run Installation Check
# This is the final and most thorough test. 'helm install --dry-run' renders the templates and
# then validates the generated manifests against the Kubernetes API schema. This catches
# API version compatibility issues or other cluster-specific problems.
echo ""
echo "--- Step 4: Performing comprehensive dry run installation ---"
for chart in "${CHARTS[@]}"; do
  CHART_PATH="${CHARTS_DIR}/${chart}/"
  echo "📦 Performing dry run for ${chart}..."
  helm install --dry-run "${chart}-test" "${CHART_PATH}" >/dev/null
  echo "✅ Dry run successful for ${chart}."
done


echo "============================================================="
echo "🎉 All specified Helm charts validated successfully!"
echo "============================================================="