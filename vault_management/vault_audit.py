#!/usr/bin/env python3
"""
STERILIZATION POUCH FACTORY — Vault Audit Script
Enumerates all files in every subfolder and produces a JSON snapshot.
"""
import subprocess
import json
import datetime

VAULT_ROOT_ID = "1sJilvwjRUiX7v2bbLAIDEZnd-qy5_QxY"

FOLDERS = [
    {"name": "00 - Artwork",                  "id": "1aO0z4P21kBaG1u1eTMuq7Kv7qsiXsJht"},
    {"name": "01 - Feasibility Study Reports","id": "1oRHFuv2j1vLCtWSA2J-fqG1P_-WbYEz3"},
    {"name": "02 - Raw Material Analysis",    "id": "1gw1sBBa97ECkeQXCSIq_fNi44qt9zF7f"},
    {"name": "03 - Machinery and Equipment",  "id": "1btTNq7TEu7cIIWwIvSKlUlpljZzzzNqo"},
    {"name": "04 - Financial Projections",    "id": "1lg7p1P0MApTxYPnvgHOo3QDcRb039cet"},
    {"name": "05 - Product Portfolio",        "id": "1wVNyz1TOmqP1ySDpDqhkVF-r80y9cR1d"},
    {"name": "06 - Source Data Files",        "id": "1BCVx3ohbqyjVXtSNiNeN5yk-RRs6Gb-s"},
    {"name": "07 - Technical References",     "id": "1vSZnhAkZsi0rnU6LzIOPq6DWTROzdMlg"},
    {"name": "08 - Financial Models (v1.1)",  "id": "1B2yTsCfDc7wmBrdpK0m-SIViO8DlbHhe"},
    {"name": "09 - Governance and Compliance","id": "1YSOGyb_9BEUDopKRbCrMkTjkwxD6S_YZ"},
    {"name": "10 - Pipeline Scripts",         "id": "1oWFsV_z9NHU3_l5OTx_lzEcAcMCdPxCj"},
    {"name": "11 - Full Illustrated Study",   "id": "1XeI22OemBdjQnyvzdDifMsUgpQlZAucs"},
    {"name": "12 - Company Profile",          "id": "1nJzyls7YWWCs71VjwL-PhnS6iqlsvrLD"},
    {"name": "13 - RFQ Documents",            "id": "1WsFD0lIvAReRiQ5KQpENESEqK2v7cXZ8"},
    {"name": "Master Data Dossier",           "id": "1uWU6DeAj6yNM8zLs_P5caI0t2_ZdN8pS"},
]

def list_folder(folder_id, folder_name, depth=0, parent_path=""):
    """Recursively list all files in a folder."""
    path = f"{parent_path}/{folder_name}" if parent_path else folder_name
    params = json.dumps({
        "q": f'"{folder_id}" in parents',
        "fields": "files(id,name,mimeType,modifiedTime,size)",
        "pageSize": 1000
    })
    result = subprocess.run(
        ["gws", "drive", "files", "list", "--params", params],
        capture_output=True, text=True
    )
    try:
        data = json.loads(result.stdout)
    except Exception:
        print(f"  ERROR parsing response for {folder_name}: {result.stderr}")
        return []

    files = data.get("files", [])
    entries = []
    for f in files:
        entry = {
            "id": f.get("id"),
            "name": f.get("name"),
            "mimeType": f.get("mimeType"),
            "modifiedTime": f.get("modifiedTime"),
            "size": f.get("size", "N/A"),
            "folder": path,
            "folder_id": folder_id,
            "depth": depth
        }
        entries.append(entry)
        # Recurse into subfolders
        if f.get("mimeType") == "application/vnd.google-apps.folder":
            sub = list_folder(f["id"], f["name"], depth+1, path)
            entries.extend(sub)
    return entries

def main():
    print("=" * 70)
    print("STERILIZATION POUCH FACTORY — VAULT AUDIT")
    print(f"Audit timestamp: {datetime.datetime.utcnow().isoformat()}Z")
    print("=" * 70)

    all_entries = []
    summary = {}

    for folder in FOLDERS:
        print(f"\nScanning: {folder['name']} ...")
        entries = list_folder(folder["id"], folder["name"])
        # Filter out subfolder entries from count (only count files)
        file_entries = [e for e in entries if e["mimeType"] != "application/vnd.google-apps.folder"]
        print(f"  -> {len(file_entries)} files found (including subfolders)")
        all_entries.extend(entries)
        summary[folder["name"]] = {
            "folder_id": folder["id"],
            "total_files": len(file_entries),
            "files": file_entries
        }

    # Build snapshot
    snapshot = {
        "generated_at": datetime.datetime.utcnow().isoformat() + "Z",
        "vault_root_id": VAULT_ROOT_ID,
        "total_files": sum(v["total_files"] for v in summary.values()),
        "folders": summary
    }

    with open("/home/ubuntu/vault_snapshot.json", "w") as f:
        json.dump(snapshot, f, indent=2)

    print(f"\n{'=' * 70}")
    print(f"AUDIT COMPLETE — {snapshot['total_files']} total files across {len(FOLDERS)} folders")
    print(f"Snapshot saved to: /home/ubuntu/vault_snapshot.json")
    print("=" * 70)

    return snapshot

if __name__ == "__main__":
    main()
