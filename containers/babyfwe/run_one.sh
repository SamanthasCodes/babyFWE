#!/usr/bin/env bash
set -euo pipefail
./run_babyfwe.sh \
  -r "/Users/samanthaeaton/Library/CloudStorage/OneDrive-UniversityofTexasatSanAntonio/PhD/babyFWE/derivates/dhcp" \
  --first \
  -i babyfwe:latest \
  --cmd "python /app/scripts/run_babyFWE.py --dwi \"\$(find {in} -maxdepth 1 -type f -name '*_dwi.nii*' | head -n1)\" --bval \"\$(find {in} -maxdepth 1 -type f -name '*.bval' | head -n1)\" --bvec \"\$(find {in} -maxdepth 1 -type f -name '*.bvec' | head -n1)\" --out {out} --subject \"\$(basename \$(dirname {in}))\""
