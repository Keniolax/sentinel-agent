"""Exports architecture.png from architecture.excaliflow with Excaliflow (awesome-llm-apps
@874bc13, advanced_llm_apps/excaliflow) running on http://localhost:3000, using the
installed Google Chrome through Playwright:
    uv run --with playwright==1.65.0 python diagram/export_png.py
"""

import base64
from pathlib import Path

from playwright.sync_api import sync_playwright

here = Path(__file__).parent
scene = (here / "architecture.excaliflow").read_text()
with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    page = browser.new_page(viewport={"width": 1600, "height": 1100})
    page.goto("http://localhost:3000/")
    page.wait_for_function("typeof importExcalidrawJson === 'function'")
    page.evaluate("s => importExcalidrawJson(s)", scene)
    data = page.evaluate("() => renderCroppedOffscreenCanvas(2, 0).toDataURL('image/png')")
    browser.close()
(here / "architecture.png").write_bytes(base64.b64decode(data.split(",", 1)[1]))
print("wrote architecture.png")
