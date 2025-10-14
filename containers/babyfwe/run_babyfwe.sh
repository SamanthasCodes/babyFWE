#!/usr/bin/env bash
set -euo pipefail

# ---- Defaults (override with flags) ----
IMAGE="${IMAGE:-yourusername/babyfwe:latest}"     # Docker Hub image
ROOT=""                                           # dataset root (required)
OUT="${OUT:-$PWD/out}"                            # output root
LOGS="${LOGS:-$PWD/logs}"                         # logs root
ENGINE="${ENGINE:-docker}"                        # docker|podman
PIPELINE_CMD="${PIPELINE_CMD:-python /app/run_babyfwe.py --in {in} --out {out}}"
DRYRUN=0
FIRST_ONLY=0
SUBJECT=""
N_JOBS=1

usage() {
  cat <<EOF
Usage: $(basename "$0") -r /path/to/dataset_root [-i image[:tag]] [options]

Required:
  -r, --root PATH         Dataset root (parent of 'derivatives' or 'derivates')

Optional:
  -i, --image NAME:TAG    Container image (default: $IMAGE)
  -o, --out PATH          Output dir root (default: $OUT)
  -l, --logs PATH         Logs dir root (default: $LOGS)
  -e, --engine ENGINE     docker|podman (default: $ENGINE)
  -s, --subject ID        Run exactly this subject (e.g., sub-0001)
  -1, --first             Run the first discovered subject only
  -n, --jobs N            Parallel jobs (GNU parallel) [default: $N_JOBS]
      --dry-run           Print what would run, do nothing
      --cmd "CMD ..."     Pipeline command template (uses {in} and {out})
  -h, --help              Show help

Notes:
• Auto-detects paths like */deriv*/dhcp/sub-*/dwi (handles 'derivatives' or 'derivates').
• Inside the container, your dataset mounts at /data and outputs at /out.
• PIPELINE_CMD template can be overridden, uses {in} (subject dwi dir) and {out} (subject out dir).
EOF
}

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--root) ROOT="$2"; shift 2;;
    -i|--image) IMAGE="$2"; shift 2;;
    -o|--out) OUT="$2"; shift 2;;
    -l|--logs) LOGS="$2"; shift 2;;
    -e|--engine) ENGINE="$2"; shift 2;;
    -s|--subject) SUBJECT="$2"; shift 2;;
    -1|--first) FIRST_ONLY=1; shift;;
    -n|--jobs) N_JOBS="$2"; shift 2;;
    --dry-run) DRYRUN=1; shift;;
    --cmd) PIPELINE_CMD="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "${ROOT}" ]]; then
  echo "ERROR: --root is required."; usage; exit 1
fi

# ---- Normalize and check paths ----
ROOT="$(cd "${ROOT}" && pwd)"
OUT="$(mkdir -p "${OUT}" && cd "${OUT}" && pwd)"
LOGS="$(mkdir -p "${LOGS}" && cd "${LOGS}" && pwd)"

# ---- Find subject DWI dirs (handles derivatives/derivates) ----
# Matches: */deriv*/dhcp/sub-*/dwi
mapfile -t DWI_DIRS < <(find "${ROOT}" -type d -path "*/deriv*/dhcp/sub-*/dwi" | sort)

if [[ ${#DWI_DIRS[@]} -eq 0 ]]; then
  echo "ERROR: No DWI directories found under ${ROOT} matching */deriv*/dhcp/sub-*/dwi"
  exit 1
fi

# ---- Filter by subject (if provided) ----
if [[ -n "${SUBJECT}" ]]; then
  DWI_DIRS=($(printf '%s\n' "${DWI_DIRS[@]}" | awk -v s="${SUBJECT}" -F/ '($0 ~ "/"s"/dwi$"){print $0}'))
  if [[ ${#DWI_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: Subject ${SUBJECT} not found with a dwi directory."
    exit 1
  fi
fi

# ---- First only ----
if [[ $FIRST_ONLY -eq 1 ]]; then
  DWI_DIRS=("${DWI_DIRS[0]}")
fi

# ---- Container engine check ----
if ! command -v "${ENGINE}" >/dev/null 2>&1; then
  echo "ERROR: ${ENGINE} not found on PATH."
  exit 1
fi

# ---- Runner for one subject ----
run_one() {
  local dwi_dir="$1"
  local sub_id
  sub_id="$(basename "$(dirname "${dwi_dir}")")"  # sub-XXXX

  local out_sub="${OUT}/${sub_id}"
  mkdir -p "${out_sub}" "${LOGS}"

  # Construct command with placeholders replaced
  local in_in_container out_in_container
  in_in_container="/data${dwi_dir#"${ROOT}"}"
  out_in_container="/out/${sub_id}"

  local cmd="${PIPELINE_CMD}"
  cmd="${cmd//\{in\}/${in_in_container}}"
  cmd="${cmd//\{out\}/${out_in_container}}"

  # Log files
  local log="${LOGS}/${sub_id}.log"

  # Container run
  local base_run=( "${ENGINE}" run --rm
                   -v "${ROOT}:/data:ro"
                   -v "${OUT}:/out"
                   "${IMAGE}" bash -lc "${cmd}" )

  echo "[INFO] ${sub_id}"
  echo "       IN : ${dwi_dir}"
  echo "       OUT: ${out_sub}"
  echo "       CMD: ${cmd}"
  echo "       LOG: ${log}"

  if [[ $DRYRUN -eq 1 ]]; then
    return 0
  fi

  # Execute and tee logs
  set +e
  "${base_run[@]}" > >(tee "${log}") 2> >(tee -a "${log}" >&2)
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "[ERROR] ${sub_id} failed (rc=${rc}). Check ${log}"
    return $rc
  fi
}

export -f run_one
export ROOT OUT LOGS IMAGE ENGINE PIPELINE_CMD DRYRUN

# ---- Execute (optionally parallel) ----
echo "[INFO] Found ${#DWI_DIRS[@]} subject(s). Starting..."
if [[ "${N_JOBS}" -gt 1 ]]; then
  if ! command -v parallel >/dev/null 2>&1; then
    echo "ERROR: GNU parallel not found, install it or use -n 1"
    exit 1
  fi
  printf '%s\n' "${DWI_DIRS[@]}" | parallel -j "${N_JOBS}" run_one {}
else
  for d in "${DWI_DIRS[@]}"; do
    run_one "${d}"
  done
fi

echo "[DONE] All requested subjects completed."
