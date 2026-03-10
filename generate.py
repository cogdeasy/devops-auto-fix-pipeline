# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "weasyprint>=62.0",
#   "markdown>=3.5",
# ]
# ///
"""
Generate HSBC-branded .pdf from testing/E2E-GUIDE.md
Styled to match HSBC-Pilot-Progress.pdf
"""

import re, pathlib, textwrap, base64

BASE = pathlib.Path(__file__).parent
MD_FILE = BASE / "testing" / "E2E-GUIDE.md"
PDF_OUT = BASE / "testing" / "AI-Auto-Fix-Pipeline-E2E-Guide.pdf"

# Logos — reuse from hsbc-pilot project if available, otherwise text fallback
HSBC_LOGO = pathlib.Path.home() / "Code" / "work" / "hsbc-pilot" / "assets" / "hsbc-logo.png"
COG_LOGO = pathlib.Path.home() / "Code" / "work" / "hsbc-pilot" / "assets" / "cognition-logo.png"


def build_pdf(md_text):
    import markdown as md_lib
    from weasyprint import HTML

    html_body = md_lib.markdown(md_text, extensions=['tables', 'fenced_code'])

    # ── Status badges ────────────────────────────────────────────────
    status_colours = {
        'Simple':   'status-green',
        'Medium':   'status-amber',
        'Complex':  'status-red',
        '~5 min':   'status-grey',
        '~10 min':  'status-grey',
        'compilation':  'status-blue',
        'test_failure': 'status-amber',
        'dependency':   'status-amber',
        'deployment':   'status-red',
        'Manual':       'status-blue',
        'Automated':    'status-green',
        'Windsurf only':        'status-grey',
        'MCP servers configured': 'status-grey',
        'MCP configured':       'status-grey',
    }
    for label, cls in status_colours.items():
        html_body = html_body.replace(
            f'<strong>{label}</strong>',
            f'<span class="status-badge {cls}">{label}</span>'
        )

    # ── Build cover page ─────────────────────────────────────────────
    logo_html = ""
    if HSBC_LOGO.exists() and COG_LOGO.exists():
        hsbc_b64 = base64.b64encode(HSBC_LOGO.read_bytes()).decode()
        cog_b64 = base64.b64encode(COG_LOGO.read_bytes()).decode()
        logo_html = (
            f'<div class="cover-header">'
            f'<img class="logo-hsbc" src="data:image/png;base64,{hsbc_b64}" alt="HSBC" />'
            f'<span class="cover-pipe"></span>'
            f'<img class="logo-cog" src="data:image/png;base64,{cog_b64}" alt="Cognition" />'
            f'</div>'
        )
    else:
        logo_html = '<div class="cover-header"><span class="cover-label">HSBC</span></div>'

    cover = (
        f'<div class="cover">'
        f'<div class="cover-bar"></div>'
        f'{logo_html}'
        f'<div class="cover-body">'
        f'<div class="cover-title">AI Auto-Fix Pipeline</div>'
        f'<div class="cover-rule"></div>'
        f'<div class="cover-subtitle">End-to-End Testing Guide</div>'
        f'<div class="cover-date">March 2026</div>'
        f'</div>'
        f'</div>'
    )

    # Remove the H1 from the markdown output (it becomes the cover title)
    html_body = re.sub(
        r'<h1>.*?</h1>',
        '',
        html_body,
        count=1
    )

    # Wrap body
    full_body = cover + '<div class="body-content">' + html_body + '</div>'

    css = textwrap.dedent("""\
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');

    @page {
        size: A4;
        margin: 3cm 3cm 2.8cm 3cm;
        @bottom-center {
            content: counter(page);
            font-family: 'Inter', sans-serif;
            font-size: 7pt;
            color: #B0B0B0;
            letter-spacing: 1pt;
        }
        @top-right {
            content: string(section-title);
            font-family: 'Inter', sans-serif;
            font-size: 7pt;
            color: #CCCCCC;
            font-style: italic;
        }
    }
    @page :first {
        margin: 0;
        @bottom-center { content: none; }
        @top-right { content: none; }
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
        font-family: 'Inter', -apple-system, 'Helvetica Neue', sans-serif;
        font-size: 9.2pt;
        line-height: 1.72;
        color: #4D4D4D;
        font-weight: 400;
    }

    /* ── Cover page ──────────────────────────── */
    .cover {
        page-break-after: always;
        width: 210mm;
        height: 297mm;
        position: relative;
        display: flex;
        flex-direction: column;
    }
    .cover-bar {
        width: 100%;
        height: 4px;
        background: #DB0011;
    }
    .cover-header {
        display: flex;
        align-items: center;
        padding: 28px 3cm 0 3cm;
    }
    .logo-hsbc {
        height: 18px;
        width: auto;
    }
    .cover-pipe {
        display: inline-block;
        width: 1px;
        height: 20px;
        background: #D0D0D0;
        margin: 0 16px;
    }
    .logo-cog {
        height: 38px;
        width: auto;
    }
    .cover-body {
        padding: 0 3cm;
        margin-top: 6.5cm;
    }
    .cover-label {
        font-family: 'Inter', sans-serif;
        font-size: 28pt;
        font-weight: 700;
        color: #DB0011;
    }
    .cover-title {
        font-family: 'Inter', sans-serif;
        font-size: 28pt;
        font-weight: 600;
        color: #222222;
        letter-spacing: -0.6pt;
        line-height: 1.2;
        margin-bottom: 22px;
    }
    .cover-rule {
        width: 40px;
        height: 3px;
        background: #DB0011;
        margin-bottom: 20px;
    }
    .cover-subtitle {
        font-family: 'Inter', sans-serif;
        font-size: 10.5pt;
        font-weight: 400;
        color: #777777;
        letter-spacing: 0.2pt;
        margin-bottom: 6px;
    }
    .cover-date {
        font-family: 'Inter', sans-serif;
        font-size: 9pt;
        font-weight: 400;
        color: #AAAAAA;
    }

    /* ── Body ────────────────────────────────── */
    .body-content {
        padding: 0;
    }

    /* ── Headings ────────────────────────────── */
    h1 {
        font-size: 17pt;
        font-weight: 600;
        color: #333333;
        letter-spacing: -0.3pt;
        margin-top: 40px;
        margin-bottom: 6px;
        padding-top: 14px;
        padding-bottom: 12px;
        border-top: 3px solid #DB0011;
        page-break-after: avoid;
    }
    h2 {
        font-size: 13pt;
        font-weight: 600;
        color: #333333;
        letter-spacing: -0.15pt;
        margin-top: 34px;
        margin-bottom: 10px;
        padding-bottom: 8px;
        border-bottom: 1px solid #E8E8E8;
        page-break-before: always;
        page-break-after: avoid;
        string-set: section-title content();
    }
    /* First h2 after cover doesn't need extra page break */
    .body-content > h2:first-child {
        page-break-before: avoid;
    }
    h3 {
        font-size: 10.5pt;
        font-weight: 600;
        color: #333333;
        margin-top: 28px;
        margin-bottom: 8px;
        padding-top: 10px;
        border-top: 1px solid #E8E8E8;
        page-break-after: avoid;
    }
    h4 {
        font-size: 8.5pt;
        font-weight: 600;
        color: #6E6E6E;
        text-transform: uppercase;
        letter-spacing: 0.8pt;
        margin-top: 20px;
        margin-bottom: 5px;
        page-break-after: avoid;
    }

    /* ── Body text ───────────────────────────── */
    p {
        margin: 0 0 9px 0;
        orphans: 3; widows: 3;
    }
    strong {
        font-weight: 600;
        color: #333333;
    }

    /* ── Lists ───────────────────────────────── */
    ul, ol {
        margin: 6px 0 14px 0;
        padding-left: 20px;
    }
    li {
        margin-bottom: 5px;
        line-height: 1.68;
    }
    li::marker {
        color: #CCCCCC;
    }

    /* ── Blockquotes ─────────────────────────── */
    blockquote {
        border-left: none;
        padding: 0;
        margin: 4px 0 12px 0;
        background: none;
        font-size: 7.5pt;
        color: #999999;
        letter-spacing: 0.2pt;
    }
    blockquote p {
        margin: 0 0 4px 0;
    }

    /* ── Tables ──────────────────────────────── */
    table {
        width: 100%;
        border-collapse: separate;
        border-spacing: 0;
        margin: 14px 0 22px 0;
        font-size: 8.2pt;
        page-break-inside: auto;
        border-radius: 6px;
        overflow: hidden;
        border: 1px solid #E8E8E8;
        word-wrap: break-word;
    }
    thead th {
        background: #F5F5F5;
        color: #888888;
        font-weight: 600;
        font-size: 7.5pt;
        text-transform: uppercase;
        letter-spacing: 0.6pt;
        padding: 10px 14px;
        text-align: left;
        border: none;
        border-bottom: 1px solid #E0E0E0;
    }
    tbody td {
        padding: 9px 14px;
        border-bottom: 1px solid #F0F0F0;
        color: #4D4D4D;
        vertical-align: top;
        line-height: 1.55;
    }
    tbody tr:last-child td {
        border-bottom: none;
    }
    tbody tr:nth-child(even) td {
        background: #FAFAFA;
    }
    tbody td strong {
        color: #333333;
    }

    /* ── Status badges ───────────────────────── */
    .status-badge {
        display: inline-block;
        font-size: inherit;
        font-weight: 600;
        padding: 2px 8px;
        border-radius: 3px;
        white-space: nowrap;
    }
    .status-green {
        background: #E8F5E9;
        color: #2E7D32;
    }
    .status-blue {
        background: #E3F2FD;
        color: #1565C0;
    }
    .status-red {
        background: #FEECEC;
        color: #C62828;
    }
    .status-amber {
        background: #FFF3E0;
        color: #E65100;
    }
    .status-grey {
        background: #F0F0F0;
        color: #757575;
    }

    /* ── Table pagination ── */
    thead {
        display: table-header-group;
    }
    tr {
        page-break-inside: avoid;
        page-break-after: auto;
    }

    /* ── Keep headings with content ── */
    h1, h2, h3, h4 {
        page-break-after: avoid;
        page-break-inside: avoid;
    }
    h2 + *, h3 + *, h4 + * {
        page-break-before: avoid;
    }
    h3 + table {
        page-break-before: avoid;
    }

    /* ── Horizontal rules ────────────────────── */
    hr {
        border: none;
        width: 40px;
        height: 3px;
        background: #DB0011;
        margin: 28px 0;
        page-break-after: avoid;
    }

    /* ── Code ────────────────────────────────── */
    code {
        font-family: 'SF Mono', 'Fira Code', Menlo, monospace;
        font-size: 8pt;
        background: #F4F4F4;
        padding: 2px 6px;
        border-radius: 3px;
        color: #444444;
        border: 1px solid #ECECEC;
    }
    pre {
        background: #F8F8F8;
        border: 1px solid #E8E8E8;
        border-radius: 4px;
        padding: 12px 16px;
        margin: 10px 0 16px 0;
        overflow-x: auto;
        page-break-inside: avoid;
    }
    pre code {
        background: none;
        border: none;
        padding: 0;
        font-size: 7.5pt;
        line-height: 1.6;
    }

    /* ── Links ───────────────────────────────── */
    a {
        color: #DB0011;
        text-decoration: none;
    }
    """)

    full_html = f"""<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<style>{css}</style>
</head><body>{full_body}</body></html>"""

    HTML(string=full_html).write_pdf(str(PDF_OUT))
    print(f"PDF saved: {PDF_OUT}")
    import os
    size = os.path.getsize(str(PDF_OUT))
    print(f"Size: {size:,} bytes ({size // 1024} KB)")


if __name__ == "__main__":
    md_text = MD_FILE.read_text()
    build_pdf(md_text)
    print("Done.")
