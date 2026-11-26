"""Writes architecture.excaliflow (Excalidraw JSON that Excaliflow imports)."""

import json
import random
from pathlib import Path

random.seed(20)
CARBON, BLUE, PURPLE, EMERALD, AMBER, ROSE, CYAN = (
    "#171717", "#0070f3", "#7928ca", "#10b981", "#f59e0b", "#ef4444", "#06b6d4")
TINT = {BLUE: "#e6f0ff", PURPLE: "#f3e8ff", EMERALD: "#e7f8f2", AMBER: "#fff4e0", ROSE: "#fdecec",
        CYAN: "#e6f8fb", CARBON: "#f4f4f5"}
els = []


def base(kind, x, y, w, h, stroke, **kw):
    e = {"id": f"e{len(els)}", "type": kind, "x": x, "y": y, "width": w, "height": h, "angle": 0,
         "strokeColor": stroke, "backgroundColor": "transparent", "fillStyle": "solid", "strokeWidth": 2,
         "strokeStyle": "solid", "roughness": 1, "opacity": 100, "groupIds": [], "frameId": None,
         "roundness": None, "seed": random.randint(1, 2**31), "version": 1,
         "versionNonce": random.randint(1, 2**31), "isDeleted": False, "boundElements": [], "updated": 1,
         "link": None, "locked": False}
    e.update(kw)
    els.append(e)
    return e


def text(x, y, s, size=18, color=CARBON, align="left"):
    lines = s.split("\n")
    w = max(len(l) for l in lines) * size * 0.55
    h = len(lines) * size * 1.25
    if align == "center":
        x -= w / 2
    return base("text", x, y, w, h, color, strokeWidth=1, text=s, fontSize=size, fontFamily=2,
                textAlign=align, verticalAlign="top", baseline=size, containerId=None, originalText=s,
                lineHeight=1.25)


def box(x, y, w, h, color, title, sub=""):
    base("rectangle", x, y, w, h, color, backgroundColor=TINT[color], roundness={"type": 3})
    text(x + w / 2, y + 14, title, 18, CARBON, "center")
    if sub:
        text(x + w / 2, y + 42, sub, 14, "#404040", "center")


def zone(x, y, w, h, color, label):
    base("rectangle", x, y, w, h, color, strokeStyle="dashed", strokeWidth=1, roundness={"type": 3})
    text(x + 14, y + 10, label, 15, color)


def arrow(x1, y1, x2, y2, color="#525252", dashed=False):
    base("arrow", x1, y1, x2 - x1, y2 - y1, color, roundness={"type": 2},
         strokeStyle="dashed" if dashed else "solid", points=[[0, 0], [x2 - x1, y2 - y1]],
         lastCommittedPoint=None, startBinding=None, endBinding=None, startArrowhead=None,
         endArrowhead="arrow")






GREY = "#404040"
text(40, 24, "sentinel-agent: an AI support agent on Azure, attacked and caught", 28)
text(40, 64, "One job execution answers one question. Two locks guard the payroll file. Every attack step reaches Wazuh.", 15, GREY)

# GitHub
zone(40, 110, 1200, 136, BLUE, "GitHub Actions: main only, signs in with a federated credential (no stored secret)")
box(60, 145, 340, 86, BLUE, "Gate", "tests, Checkov + CKV_SENTINEL_1,\nTrivy, Semgrep, Gitleaks")
box(440, 145, 340, 86, BLUE, "Build", "image tag = hash of its inputs; Trivy scan")
box(820, 145, 400, 86, BLUE, "Deploy", "terraform apply as id-sentinel-deploy")
arrow(404, 188, 436, 188, BLUE)
arrow(784, 188, 816, 188, BLUE)

# Bootstrap group
zone(40, 260, 300, 175, PURPLE, "rg-sentinel-bootstrap")
box(60, 290, 260, 62, PURPLE, "Registry (ACR)", "image by digest")
box(60, 362, 260, 62, PURPLE, "Terraform state", "Entra ID only, no keys")
arrow(610, 235, 300, 291, BLUE)
arrow(1020, 235, 1020, 256, BLUE)

# Lab group
zone(370, 260, 870, 560, EMERALD, "rg-sentinel-lab: CI is Contributor here and may grant only 3 read roles")
zone(390, 295, 420, 230, CYAN, "snet-jobs: NSG allows only Azure services out")
box(410, 335, 380, 170, CYAN, "Container Apps job",
    "agent + Ollama qwen2.5:1.5b\n+ mock orders API, on loopback\nidentity: id-sentinel-agent\nAcrPull + read 'knowledge' only")
arrow(320, 321, 406, 360, PURPLE)

box(850, 300, 370, 70, AMBER, "Storage: 'knowledge'", "kb/*.md (Storage Blob Data Reader)")
box(850, 390, 370, 70, ROSE, "Storage: 'finance'", "records/payroll.csv: no role, refused")
arrow(794, 360, 846, 335, AMBER)
arrow(794, 420, 846, 425, ROSE, dashed=True)
text(800, 470, "lock 1: the tool's key check\nlock 2: Azure RBAC", 13, ROSE)

box(850, 545, 370, 90, CARBON, "Log Analytics",
    "ContainerAppConsoleLogs\nStorageBlobLogs, AzureActivity")
arrow(600, 509, 900, 541, GREY)
arrow(1035, 464, 1035, 541, GREY, dashed=True)
text(1045, 495, "resource logs", 13, GREY)

zone(390, 560, 420, 240, AMBER, "snet-siem: no inbound port at all")
box(410, 600, 380, 80, AMBER, "Collector (every minute)",
    "managed identity -> Log Analytics API\n-> /var/log/sentinel/azure.json")
box(410, 700, 380, 90, AMBER, "Wazuh 4.14 manager + indexer",
    "100810-100811: blob read, agent event\n100820-100824: the attack rules")
arrow(846, 600, 794, 630, GREY)
arrow(600, 684, 600, 696, AMBER)

# Operator
zone(40, 460, 300, 260, CARBON, "Operator (az CLI)")
box(60, 495, 260, 90, CARBON, "scripts/ask.sh", "start one execution\nwith QUESTION + RUN_ID")
box(60, 605, 260, 90, CARBON, "scripts/verify-siem.sh", "Run Command: grep Wazuh\nfor the run and its reads")
arrow(324, 540, 406, 430, GREY)
arrow(324, 650, 406, 740, GREY)

# Week 19: the attack chain and what caught it
zone(40, 850, 1200, 190, ROSE, "Attack chain (run against this lab only), and what stops or catches each step")
box(60, 885, 370, 135, ROSE, "A. Poisoned help article",
    "prompt injection (LLM01) tells the model\nto read the payroll: tool misuse (ASI02)\nblocked: lock 1, the tool's key check\ncaught: 100822 on a finance tool call")
box(455, 885, 370, 135, ROSE, "B. Read and leak the payroll",
    "data from cloud storage (T1530)\nblocked: lock 2, RBAC -> 403\ncaught: 100820 any finance access,\n100821 a successful read (level 14)")
box(850, 885, 370, 135, ROSE, "C. Cloud foothold",
    "Run Command on a VM (T1078.004),\nrole grant on finance (T1098)\ncaught: 100823, 100824\nblocked in CI: CKV_SENTINEL_1")

doc = {"type": "excalidraw", "version": 2, "source": "sentinel-agent", "elements": els,
       "appState": {"gridSize": None, "viewBackgroundColor": "#ffffff"}, "files": {}}
Path(__file__).with_name("architecture.excaliflow").write_text(json.dumps(doc, indent=1))
print(len(els), "elements")
