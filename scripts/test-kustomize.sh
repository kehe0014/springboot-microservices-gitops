#!/bin/bash

# ==============================================================================
# Kustomize Overlay Validation Script with Dry-Run
# ==============================================================================

set -Eeuo pipefail

function on_error {
  echo ""
  echo "❌ An error occurred on line ${LINENO}." >&2
  echo "Exiting with status 1." >&2
  exit 1
}

trap on_error ERR

# --- Script Configuration ---
KUSTOMIZE_BASE_DIR="../k8s/kustomize/base"
KUSTOMIZE_OVERLAYS_DIR="../k8s/kustomize/environments"

# --- Helper Functions ---
function check_directory_exists {
  local dir_path="$1"
  if [[ ! -d "${dir_path}" ]]; then
    echo "❌ Error: Directory '${dir_path}' not found. Please ensure the path is correct."
    exit 1
  fi
}

function check_file_exists {
  local file_path="$1"
  if [[ ! -f "${file_path}" ]]; then
    echo "❌ Error: File '${file_path}' not found. Please ensure the path is correct."
    exit 1
  fi
}

# --- Main Logic ---
echo "=============================================="
echo "🚀 Starting Kustomize Overlay Validation"
echo "=============================================="

# --- Step 1: Pre-flight Checks ---
echo "--- Step 1: Running Pre-flight Checks ---"
check_directory_exists "${KUSTOMIZE_BASE_DIR}"
check_directory_exists "${KUSTOMIZE_OVERLAYS_DIR}"

echo "📝 Checking for base kustomization.yaml files..."
for service_dir in "${KUSTOMIZE_BASE_DIR}"/*/; do
  service_name=$(basename "${service_dir}")
  if [[ -d "${service_dir}" ]]; then
    check_file_exists "${service_dir}/kustomization.yaml"
    echo "✅ Base kustomization.yaml for ${service_name} exists."
  fi
done
echo "All base kustomization files are present."
echo ""

# --- Step 2: Building and Validating Overlays ---
echo "--- Step 2: Building and Validating Overlays ---"

# Loop through each environment directory (e.g., dev, prod, staging)
for env_dir in "${KUSTOMIZE_OVERLAYS_DIR}"/*/; do
  if [[ -d "${env_dir}" ]]; then
    ENV_NAME=$(basename "${env_dir}")
    
    echo "📝 Validating overlay for environment: ${ENV_NAME}..."
    
    KUSTOMIZATION_FILE="${env_dir}/kustomization.yaml"
    check_file_exists "${KUSTOMIZATION_FILE}"
    
    if [[ ! -s "${KUSTOMIZATION_FILE}" ]]; then
      echo "❌ Error: Kustomization file '${KUSTOMIZATION_FILE}' is empty."
      exit 1
    fi

    # Navigate to the specific environment directory
    cd "${env_dir}"

    # Build the manifests and check for empty output
    BUILD_OUTPUT=$(kustomize build .)
    if [[ -z "${BUILD_OUTPUT}" ]]; then
      echo "❌ Kustomize build produced no output. This might indicate an issue with file references."
      exit 1
    fi
    
    # --- Step 3: Performing a Dry-Run Deployment ---
    echo "🔍 Performing dry-run deployment for ${ENV_NAME}..."
    
    # The 'kustomize build' output is piped directly to 'kubectl apply --dry-run=client'
    # This checks if the generated manifests are syntactically and semantically valid
    echo "${BUILD_OUTPUT}" | kubectl apply --dry-run=client -f - >/dev/null
    
    echo "✅ Kustomize build and dry-run successful for ${ENV_NAME}."
    
    cd - >/dev/null # Go back to the previous directory
  fi
done

echo ""
echo "=============================================="
echo "🎉 Kustomize overlays validated successfully!"
echo "=============================================="