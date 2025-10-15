#!/usr/bin/env python3
import argparse
import pathlib as p
import sys

import nibabel as nib
import numpy as np

# NRDG FWE
import fwe  # make sure your venv linter is using .venv; inside container this is preinstalled.

def parse_args():
    ap = argparse.ArgumentParser(description="Run NRDG FWE on a single subject.")
    ap.add_argument("--dwi",  required=True, help="Path to dwi .nii/.nii.gz")
    ap.add_argument("--bval", required=True, help="Path to .bval file")
    ap.add_argument("--bvec", required=True, help="Path to .bvec file")
    ap.add_argument("--mask", default="", help="Optional brain mask .nii/.nii.gz")
    ap.add_argument("--out",  required=True, help="Output directory for subject")
    ap.add_argument("--subject", required=True, help="BIDS subject ID (e.g., sub-CC00339XX18)")
    ap.add_argument("--session", default="", help="BIDS session ID (e.g., ses-107200, optional)")
    return ap.parse_args()

def main():
    args = parse_args()
    out_dir = p.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Load inputs
    dwi_img  = nib.load(args.dwi)
    dwi_data = dwi_img.get_fdata(dtype=np.float32)

    bvals = np.loadtxt(args.bval)
    bvecs = np.loadtxt(args.bvec)

    mask = None
    if args.mask:
        try:
            mask = nib.load(args.mask).get_fdata().astype(bool)
        except Exception:
            mask = None

    # ---- FWE call (fill with the exact NRDG API you want) ----
    # The NRDG repo exposes a few entry points; commonly you’d:
    #  1) Fit the free-water elimination model to get tissue tensor + FW fraction
    #  2) Save FW-corrected DWI and/or FW maps (and tensor-derived maps)
    #
    # Pseudocode (replace with actual calls per NRDG docs):
    #
    # from fwe import fit
    # result = fit(dwi=dwi_data, bvals=bvals, bvecs=bvecs, mask=mask,
    #              lambda_fw=1e-3, max_iter=100, ...)
    #
    # Save outputs:
    # nib.save(nib.Nifti1Image(result.fw_fraction, dwi_img.affine, dwi_img.header),
    #          out_dir / f"{args.subject}_{args.session or 'nosess'}_fwe_fwfrac.nii.gz")
    # nib.save(nib.Nifti1Image(result.dwi_corrected, dwi_img.affine, dwi_img.header),
    #          out_dir / f"{args.subject}_{args.session or 'nosess'}_fwe_dwi_corrected.nii.gz")
    #
    # If the package provides a CLI wrapper (e.g., `fwe` command), you could invoke that via subprocess instead.

    # === minimal output so we can verify end-to-end ===
    import os, json
    os.makedirs(args.out, exist_ok=True)
    manifest = {
        "subject": args.subject,
        "dwi": args.dwi,
        "bval": args.bval,
        "bvec": args.bvec,
    }
    with open(os.path.join(args.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    open(os.path.join(args.out, "_SUCCESS"), "w").close()
    print(f"[DONE] Wrote {os.path.join(args.out, 'manifest.json')} and _SUCCESS")

    return 0

if __name__ == "__main__":
    sys.exit(main())
