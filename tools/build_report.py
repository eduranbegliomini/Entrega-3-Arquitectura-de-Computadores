#!/usr/bin/env python3
"""Build docs/informe.pdf from docs/informe.md.

Markdown -> HTML (python package `markdown`, extension `tables`) -> PDF with
a headless Chromium browser (Chrome or Edge). Image paths in the Markdown are
relative to docs/.

    python tools/build_report.py
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
SRC = DOCS / "informe.md"
HTML = DOCS / "informe.html"
PDF = DOCS / "informe.pdf"

CSS = """
@page { size: A4; margin: 18mm 16mm 18mm 16mm; }
body { font-family: Calibri, 'Segoe UI', Arial, sans-serif; font-size: 10.5pt; line-height: 1.38; color: #000; }
h1 { font-size: 20pt; margin: 0 0 6pt; }
h2 { font-size: 14.5pt; margin: 16pt 0 6pt; border-bottom: 1px solid #000; padding-bottom: 2pt; page-break-after: avoid; }
h3 { font-size: 12pt; margin: 12pt 0 4pt; page-break-after: avoid; }
p, li { text-align: justify; }
table { border-collapse: collapse; margin: 6pt 0 10pt; font-size: 9pt; width: 100%; page-break-inside: avoid; }
th, td { border: 0.6pt solid #000; padding: 2.5pt 5pt; vertical-align: top; }
th { background: #eee; }
code { font-family: Consolas, monospace; font-size: 8.8pt; }
pre { border: 0.6pt solid #000; padding: 5pt; font-size: 8.3pt; line-height: 1.25; white-space: pre-wrap; page-break-inside: avoid; }
img { max-width: 100%; display: block; margin: 6pt auto; page-break-inside: avoid; }
.fig { text-align: center; font-size: 9pt; margin-bottom: 10pt; }
blockquote { border-left: 3pt solid #000; margin: 6pt 0; padding: 2pt 8pt; }
"""


def find_browser() -> str:
    for cand in (
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ):
        if Path(cand).exists():
            return cand
    for name in ("chromium", "chromium-browser", "google-chrome", "msedge"):
        if shutil.which(name):
            return shutil.which(name)
    sys.exit("No Chrome/Edge/Chromium found to print the PDF")


def main() -> int:
    body = markdown.markdown(SRC.read_text(encoding="utf-8"), extensions=["tables", "fenced_code", "toc"])
    HTML.write_text(f"<!doctype html><html lang='es'><head><meta charset='utf-8'><title>Informe Proyecto 3</title>"
                    f"<style>{CSS}</style></head><body>{body}</body></html>", encoding="utf-8")
    subprocess.run([find_browser(), "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    f"--print-to-pdf={PDF}", HTML.resolve().as_uri()], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"wrote {PDF}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
