function Get-EndpointCheckerHtmlCss {
    return @'
:root {
    --bg: #f3f5f8;
    --card: #ffffff;
    --text: #1f2937;
    --muted: #6b7280;
    --border: #d8dee7;
    --pass-bg: #e7f7ea;
    --pass-text: #1f7a35;
    --warn-bg: #fff6dd;
    --warn-text: #9a6a00;
    --fail-bg: #fdeaea;
    --fail-text: #9e1f1f;
    --heading: #0f3d66;
}

body {
    margin: 0;
    padding: 24px;
    background: linear-gradient(180deg, #f0f4f8 0%, #f8fafc 50%, #eef2f7 100%);
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    color: var(--text);
}

.container {
    max-width: 1180px;
    margin: 0 auto;
}

header {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 20px;
    box-shadow: 0 3px 10px rgba(15, 61, 102, 0.06);
}

h1 {
    margin: 0;
    color: var(--heading);
    font-size: 28px;
}

.subtitle {
    margin-top: 8px;
    color: var(--muted);
    font-size: 14px;
}

.meta-grid {
    margin-top: 16px;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    gap: 10px;
}

.meta-item {
    background: #f8fafc;
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 10px;
}

.meta-label {
    font-size: 12px;
    color: var(--muted);
}

.meta-value {
    font-size: 14px;
    margin-top: 4px;
    font-weight: 600;
}

section {
    margin-top: 20px;
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 10px;
    box-shadow: 0 3px 10px rgba(15, 61, 102, 0.05);
}

.section-header {
    padding: 16px 18px;
    border-bottom: 1px solid var(--border);
}

.section-header h2 {
    margin: 0;
    color: var(--heading);
    font-size: 20px;
}

.section-body {
    padding: 14px 18px 18px 18px;
}

table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
}

th,
td {
    border: 1px solid var(--border);
    padding: 10px;
    text-align: left;
    vertical-align: top;
}

th {
    background: #f6f8fb;
    font-weight: 700;
}

.status-pill {
    display: inline-block;
    padding: 4px 10px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 700;
}

.status-pass {
    background: var(--pass-bg);
    color: var(--pass-text);
}

.status-warn {
    background: var(--warn-bg);
    color: var(--warn-text);
}

.status-fail {
    background: var(--fail-bg);
    color: var(--fail-text);
}

.summary-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
    gap: 10px;
    margin-top: 12px;
}

.summary-card {
    border: 1px solid var(--border);
    border-radius: 8px;
    background: #f9fbfe;
    padding: 12px;
}

.summary-card .label {
    color: var(--muted);
    font-size: 12px;
}

.summary-card .value {
    margin-top: 6px;
    font-size: 21px;
    font-weight: 700;
}

small.mono {
    font-family: Consolas, Monaco, monospace;
    color: var(--muted);
}

.footer-note {
    margin-top: 18px;
    color: var(--muted);
    font-size: 12px;
}

@media (max-width: 880px) {
    body {
        padding: 12px;
    }

    th,
    td {
        font-size: 12px;
        padding: 8px;
    }

    h1 {
        font-size: 23px;
    }
}
'@
}
