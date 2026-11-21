"""Writes a SideStore / AltStore source (source.json) for the FitTrack release.

The source is attached to every GitHub Release, so its URL never changes:
https://github.com/<owner>/<repo>/releases/latest/download/source.json
"""
import argparse
import datetime
import json
import os

parser = argparse.ArgumentParser()
parser.add_argument("--repo", required=True)        # owner/name
parser.add_argument("--tag", required=True)
parser.add_argument("--version", required=True)
parser.add_argument("--build", required=True)
parser.add_argument("--ipa", required=True)
parser.add_argument("--notes", default="")
parser.add_argument("--out", required=True)
args = parser.parse_args()

base = f"https://github.com/{args.repo}/releases"
download = f"{base}/download/{args.tag}"
owner = args.repo.split("/")[0]
size = os.path.getsize(args.ipa)
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

version = {
    "version": args.version,
    "buildVersion": args.build,
    "date": date,
    "localizedDescription": args.notes or f"Build {args.build}",
    "downloadURL": f"{download}/FitTrack.ipa",
    "size": size,
    "minOSVersion": "16.0",
}

source = {
    "name": "FitTrack",
    "identifier": f"io.github.{owner.lower()}.fittrack.source",
    "sourceURL": f"{base}/latest/download/source.json",
    "iconURL": f"{download}/icon.png",
    "tintColor": "34C759",
    "apps": [
        {
            "name": "FitTrack",
            "bundleIdentifier": "com.example.fittrack",
            "developerName": owner,
            "subtitle": "Calories, macros and Apple Health",
            "localizedDescription": (
                "Track daily calories and macros on an hourly food log. Scan barcodes "
                "(with verified / unverified nutrition tags), photograph nutrition labels "
                "or whole meals for AI estimates, and sync with Apple Health."
            ),
            "iconURL": f"{download}/icon.png",
            "tintColor": "34C759",
            "category": "lifestyle",
            "screenshots": [],
            "versions": [version],
            # Legacy top-level fields for older AltStore/SideStore builds.
            "version": version["version"],
            "versionDate": date,
            "versionDescription": version["localizedDescription"],
            "downloadURL": version["downloadURL"],
            "size": size,
            "appPermissions": {
                "entitlements": ["com.apple.developer.healthkit"],
                "privacy": {
                    "NSCameraUsageDescription": "Scan food barcodes and photograph meals.",
                    "NSPhotoLibraryUsageDescription": "Pick a meal photo to estimate calories.",
                    "NSHealthShareUsageDescription": "Read active energy, workouts and body measurements.",
                    "NSHealthUpdateUsageDescription": "Save logged meals and weight to Apple Health.",
                },
            },
        }
    ],
    "news": [],
}

with open(args.out, "w") as f:
    json.dump(source, f, indent=2)
