#!/usr/bin/env python3
"""
STERILIZATION POUCH FACTORY — Daily Vault Check
================================================
This script:
1. Loads the previous vault snapshot (baseline)
2. Scans the live Google Drive vault for the current state
3. Diffs the two snapshots to detect:
   - NEW files (added since last check)
   - MODIFIED files (same name, different modifiedTime)
   - DELETED files (present in baseline, missing now)
4. Regenerates the MASTER_KNOWLEDGE_BASE.md with the latest state
5. Saves a dated DIFF REPORT to /home/ubuntu/vault_reports/
6. Uploads the new snapshot, KB, and report to Google Drive
7. Pushes changes to GitHub

Usage:
    python3 daily_vault_check.py
"""

import subprocess
import json
import datetime
import os
import shutil

# ─── Configuration ────────────────────────────────────────────────────────────
VAULT_ROOT_ID   = "1sJilvwjRUiX7v2bbLAIDEZnd-qy5_QxY"
SNAPSHOT_PATH   = "/home/ubuntu/vault_snapshot.json"
KB_PATH         = "/home/ubuntu/MASTER_KNOWLEDGE_BASE.md"
REPORTS_DIR     = "/home/ubuntu/vault_reports"
REPO_DIR        = "/home/ubuntu/ASTRA-TAWZEEF-V1"

# Google Drive folder for vault management docs (09 - Governance and Compliance)
GOVERNANCE_FOLDER_ID = "1YSOGyb_9BEUDopKRbCrMkTjkwxD6S_YZ"

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

os.makedirs(REPORTS_DIR, exist_ok=True)

# ─── Helpers ──────────────────────────────────────────────────────────────────
def gws_list_folder(folder_id, folder_name, depth=0, parent_path=""):
    """Recursively list all files in a Google Drive folder."""
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
        print(f"  [ERROR] Could not parse response for folder: {folder_name}")
        return []

    entries = []
    for f in data.get("files", []):
        entry = {
            "id": f.get("id"),
            "name": f.get("name"),
            "mimeType": f.get("mimeType"),
            "modifiedTime": f.get("modifiedTime"),
            "size": f.get("size", "N/A"),
            "folder": path,
            "folder_id": folder_id,
        }
        entries.append(entry)
        if f.get("mimeType") == "application/vnd.google-apps.folder":
            entries.extend(gws_list_folder(f["id"], f["name"], depth + 1, path))
    return entries


def build_snapshot():
    """Scan all vault folders and return a structured snapshot dict."""
    summary = {}
    for folder in FOLDERS:
        entries = gws_list_folder(folder["id"], folder["name"])
        file_entries = [e for e in entries if e["mimeType"] != "application/vnd.google-apps.folder"]
        summary[folder["name"]] = {
            "folder_id": folder["id"],
            "total_files": len(file_entries),
            "files": file_entries
        }
    return {
        "generated_at": datetime.datetime.utcnow().isoformat() + "Z",
        "vault_root_id": VAULT_ROOT_ID,
        "total_files": sum(v["total_files"] for v in summary.values()),
        "folders": summary
    }


def flatten_snapshot(snapshot):
    """Return a flat dict: {(folder_name, file_name): file_info}."""
    flat = {}
    for folder_name, folder_data in snapshot["folders"].items():
        for f in folder_data["files"]:
            key = (folder_name, f["name"])
            flat[key] = f
    return flat


def diff_snapshots(old_snap, new_snap):
    """Compare two snapshots and return added, modified, deleted lists."""
    old_flat = flatten_snapshot(old_snap)
    new_flat = flatten_snapshot(new_snap)

    added    = []
    modified = []
    deleted  = []

    for key, new_info in new_flat.items():
        if key not in old_flat:
            added.append({"folder": key[0], "name": key[1], "info": new_info})
        elif old_flat[key]["modifiedTime"] != new_info["modifiedTime"]:
            modified.append({
                "folder": key[0],
                "name": key[1],
                "old_modified": old_flat[key]["modifiedTime"],
                "new_modified": new_info["modifiedTime"],
                "info": new_info
            })

    for key in old_flat:
        if key not in new_flat:
            deleted.append({"folder": key[0], "name": key[1], "info": old_flat[key]})

    return added, modified, deleted


def generate_kb(snapshot):
    """Regenerate the MASTER_KNOWLEDGE_BASE.md from a snapshot."""
    lines = [
        "# MASTER KNOWLEDGE BASE — STERILIZATION POUCH FACTORY",
        "",
        "**Purpose:** Central Source-of-Truth for all documents in the Google Drive vault.",
        "Auto-generated and updated daily. When creating any new document, **always consult",
        "this file first** to check for previous versions and maintain continuity.",
        "",
        f"**Last Updated:** {snapshot['generated_at']}",
        f"**Total Files Tracked:** {snapshot['total_files']}",
        "",
        "---",
        "",
        "## Document Generation Rule",
        "",
        "> **MANDATORY:** Before generating any document, search this knowledge base for",
        "> existing versions of the same document. If a previous version exists:",
        "> 1. Download and review the previous version for context and continuity.",
        "> 2. Increment the version number (e.g., v1 → v2).",
        "> 3. Move the old file to the `ARCHIVE` subfolder of its parent folder.",
        "> 4. Upload the new version to the parent folder (circulation).",
        "> 5. Update this knowledge base.",
        "",
        "---",
        "",
        "## Vault Folder Summary",
        "",
        "| Folder Name | Folder ID | File Count |",
        "|---|---|---|",
    ]
    for folder_name, folder_data in snapshot["folders"].items():
        lines.append(f"| {folder_name} | `{folder_data['folder_id']}` | {folder_data['total_files']} |")

    lines += ["", "---", "", "## Detailed File Inventory", ""]

    for folder_name, folder_data in sorted(snapshot["folders"].items()):
        lines.append(f"### {folder_name}")
        lines.append("")
        if not folder_data["files"]:
            lines.append("> No files found in this folder.")
            lines.append("")
            continue

        lines.append("| File Name | Last Modified | Type | File ID |")
        lines.append("|---|---|---|---|")
        for fi in sorted(folder_data["files"], key=lambda x: x["name"]):
            name = fi["name"].replace("|", "\\|")
            mime = fi["mimeType"].split("/")[-1]
            lines.append(f"| {name} | {fi['modifiedTime']} | `{mime}` | `{fi['id']}` |")
        lines.append("")

    with open(KB_PATH, "w") as f:
        f.write("\n".join(lines))
    print(f"  [OK] MASTER_KNOWLEDGE_BASE.md updated ({snapshot['total_files']} files)")


def generate_diff_report(added, modified, deleted, old_snap, new_snap):
    """Write a dated diff report markdown file."""
    today = datetime.datetime.utcnow().strftime("%Y-%m-%d")
    report_path = os.path.join(REPORTS_DIR, f"vault_diff_report_{today}.md")

    lines = [
        f"# Vault Daily Diff Report — {today}",
        "",
        f"**Baseline snapshot:** {old_snap['generated_at']}",
        f"**Current snapshot:**  {new_snap['generated_at']}",
        "",
        f"| Metric | Count |",
        f"|---|---|",
        f"| New files added | {len(added)} |",
        f"| Files modified | {len(modified)} |",
        f"| Files deleted / moved | {len(deleted)} |",
        f"| Total files (current) | {new_snap['total_files']} |",
        "",
        "---",
        "",
    ]

    if added:
        lines += ["## New Files Added", ""]
        lines += ["| Folder | File Name | Modified Time |", "|---|---|---|"]
        for item in added:
            lines.append(f"| {item['folder']} | {item['name']} | {item['info']['modifiedTime']} |")
        lines.append("")

    if modified:
        lines += ["## Modified Files", ""]
        lines += ["| Folder | File Name | Previous Modified | New Modified |", "|---|---|---|---|"]
        for item in modified:
            lines.append(f"| {item['folder']} | {item['name']} | {item['old_modified']} | {item['new_modified']} |")
        lines.append("")

    if deleted:
        lines += ["## Deleted / Removed Files", ""]
        lines += ["| Folder | File Name | Last Known Modified |", "|---|---|---|"]
        for item in deleted:
            lines.append(f"| {item['folder']} | {item['name']} | {item['info']['modifiedTime']} |")
        lines.append("")

    if not added and not modified and not deleted:
        lines += ["## No Changes Detected", "", "> The vault is identical to the previous snapshot.", ""]

    lines += [
        "---",
        "",
        "*Generated automatically by the STERILIZATION POUCH FACTORY Daily Vault Check.*",
    ]

    with open(report_path, "w") as f:
        f.write("\n".join(lines))
    print(f"  [OK] Diff report saved: {report_path}")
    return report_path


def upload_to_drive(file_path, folder_id, description=""):
    """Upload a file to Google Drive using gws +upload."""
    result = subprocess.run(
        ["gws", "drive", "+upload", file_path, "--parent", folder_id],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"  [UPLOADED] {os.path.basename(file_path)} → Drive folder {folder_id}")
    else:
        print(f"  [UPLOAD ERROR] {os.path.basename(file_path)}: {result.stderr[:200]}")
    return result


def push_to_github(files_to_add, commit_message):
    """Stage, commit, and push files to GitHub."""
    if not os.path.exists(REPO_DIR):
        print("  [SKIP] GitHub repo not found locally.")
        return

    # Copy files into repo
    vault_mgmt_dir = os.path.join(REPO_DIR, "vault_management")
    os.makedirs(vault_mgmt_dir, exist_ok=True)

    for src in files_to_add:
        dst = os.path.join(vault_mgmt_dir, os.path.basename(src))
        shutil.copy2(src, dst)
        print(f"  [COPIED] {os.path.basename(src)} → {vault_mgmt_dir}")

    cmds = [
        f"cd {REPO_DIR} && git add vault_management/",
        f'cd {REPO_DIR} && git commit -m "{commit_message}" || echo "nothing to commit"',
        f"cd {REPO_DIR} && git pull --rebase origin main && git push origin main"
    ]
    for cmd in cmds:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"  [GIT] {cmd.split('&&')[-1].strip()} — OK")
        else:
            out = (result.stdout + result.stderr)[:200]
            print(f"  [GIT] {cmd.split('&&')[-1].strip()} — {out}")


# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    today = datetime.datetime.utcnow().strftime("%Y-%m-%d")
    print("=" * 70)
    print(f"STERILIZATION POUCH FACTORY — DAILY VAULT CHECK")
    print(f"Run time: {datetime.datetime.utcnow().isoformat()}Z")
    print("=" * 70)

    # 1. Load baseline snapshot
    if os.path.exists(SNAPSHOT_PATH):
        with open(SNAPSHOT_PATH) as f:
            old_snapshot = json.load(f)
        print(f"\n[1] Baseline snapshot loaded ({old_snapshot['generated_at']})")
    else:
        print("\n[1] No baseline snapshot found — this is the first run.")
        old_snapshot = None

    # 2. Scan live vault
    print("\n[2] Scanning live vault ...")
    new_snapshot = build_snapshot()
    print(f"    -> {new_snapshot['total_files']} files found across {len(FOLDERS)} folders")

    # 3. Diff
    if old_snapshot:
        print("\n[3] Comparing snapshots ...")
        added, modified, deleted = diff_snapshots(old_snapshot, new_snapshot)
        print(f"    -> Added: {len(added)}  |  Modified: {len(modified)}  |  Deleted: {len(deleted)}")
    else:
        added, modified, deleted = [], [], []
        print("\n[3] Skipping diff (no baseline).")

    # 4. Regenerate Knowledge Base
    print("\n[4] Regenerating MASTER_KNOWLEDGE_BASE.md ...")
    generate_kb(new_snapshot)

    # 5. Generate diff report
    print("\n[5] Generating diff report ...")
    report_path = generate_diff_report(
        added, modified, deleted,
        old_snapshot or new_snapshot,
        new_snapshot
    )

    # 6. Save new snapshot as baseline
    with open(SNAPSHOT_PATH, "w") as f:
        json.dump(new_snapshot, f, indent=2)
    print(f"\n[6] Snapshot updated: {SNAPSHOT_PATH}")

    # 7. Upload to Google Drive (09 - Governance and Compliance)
    print("\n[7] Uploading artifacts to Google Drive ...")
    upload_to_drive(KB_PATH, GOVERNANCE_FOLDER_ID,
                    "MASTER_KNOWLEDGE_BASE — auto-updated by daily vault check")
    upload_to_drive(report_path, GOVERNANCE_FOLDER_ID,
                    f"Vault Diff Report {today}")

    # 8. Push to GitHub
    print("\n[8] Pushing to GitHub ...")
    push_to_github(
        [KB_PATH, report_path, SNAPSHOT_PATH],
        f"chore: daily vault check {today} — {len(added)} new, {len(modified)} modified, {len(deleted)} deleted"
    )

    print("\n" + "=" * 70)
    print("DAILY VAULT CHECK COMPLETE")
    print("=" * 70)

    return {
        "added": len(added),
        "modified": len(modified),
        "deleted": len(deleted),
        "total": new_snapshot["total_files"]
    }


if __name__ == "__main__":
    main()
