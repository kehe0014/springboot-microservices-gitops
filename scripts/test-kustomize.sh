#!/bin/bash

# ==============================================================================
# Kustomize Overlay Validation Script with Self-Contained Dependencies
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
K8_S_DIR="../k8s"
KUSTOMIZE_BASE_DIR="$K8_S_DIR/kustomize/base"
KUSTOMIZE_OVERLAYS_DIR="$K8_S_DIR/kustomize/environments"

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
echo "🚀 Starting Kustomize and YAML Validation"
echo "=============================================="

# --- Step 1: Check and Install yamllint ---
echo "--- Step 1: Checking for yamllint dependency ---"
if ! command -v yamllint &> /dev/null; then
  echo "⚠️ yamllint not found. Installing now..."
  if command -v pip &> /dev/null; then
    pip install yamllint
  else
    echo "❌ Error: 'pip' command not found. Please install Python and pip to proceed."
    exit 1
  fi
  echo "✅ yamllint installed successfully."
else
  echo "✅ yamllint is already installed."
fi
echo ""

# --- Step 2: Run YAML Linting on all manifest files ---
echo "--- Step 2: Running YAML linting on all manifest files ---"
find $K8_S_DIR -type f \( -name "*.yaml" -o -name "*.yml" \) -print0 | while IFS= read -r -d '' yaml_file; do
  echo "🔍 Linting file: ${yaml_file}"
  yamllint "${yaml_file}" || { echo "❌ YAML linting failed for ${yaml_file}"; exit 1; }
done
echo "✅ All YAML files are syntactically valid."
echo ""

# --- Step 3: Validate Base Manifests with Kustomize build ---
echo "--- Step 3: Validating Base Manifests ---"
check_directory_exists "${KUSTOMIZE_BASE_DIR}"

for service_dir in "${KUSTOMIZE_BASE_DIR}"/*/; do
  if [[ -d "${service_dir}" ]]; then
    service_name=$(basename "${service_dir}")
    kustomization_file="${service_dir}/kustomization.yaml"
    check_file_exists "${kustomization_file}"
    
    echo "📝 Building base manifests for ${service_name}..."
    kustomize build "${service_dir}" | kubectl apply --dry-run=client -f - >/dev/null
    echo "✅ Base manifests for ${service_name} are valid."
  fi
done
echo ""

# --- Step 4: Building and Validating Overlays ---
echo "--- Step 4: Building and Validating Overlays ---"
check_directory_exists "${KUSTOMIZE_OVERLAYS_DIR}"

for env_dir in "${KUSTOMIZE_OVERLAYS_DIR}"/*/; do
  if [[ -d "${env_dir}" ]]; then
    ENV_NAME=$(basename "${env_dir}")
    
    echo "📝 Building and validating overlay for environment: ${ENV_NAME}..."
    
    kustomization_file="${env_dir}/kustomization.yaml"
    check_file_exists "${kustomization_file}"
    
    if [[ ! -s "${kustomization_file}" ]]; then
      echo "❌ Error: Kustomization file '${kustomization_file}' is empty."
      exit 1
    fi

    BUILD_AND_DRY_RUN_OUTPUT=$(kustomize build "${env_dir}" | kubectl apply --dry-run=client -f - 2>&1)
    
    if [[ "${BUILD_AND_DRY_RUN_OUTPUT}" =~ "Error from server" ]]; then
      echo "❌ Validation failed for ${ENV_NAME}."
      echo "${BUILD_AND_DRY_RUN_OUTPUT}"
      exit 1
    fi
    
    echo "✅ Kustomize build and dry-run successful for ${ENV_NAME}."
    echo ""
  fi
done

echo "=============================================="
echo "🎉 Kustomize and YAML files validated successfully!"
echo "=============================================="