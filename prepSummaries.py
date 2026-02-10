import pandas as pd
from docx import Document
from datetime import datetime

EXCEL_PATH = "Briefing Data Pull Example.xlsx"
TEMPLATE_PATH = "Briefing_Template.docx"
OUTPUT_PATH = "Generated_Briefing.docx"

#formatters
def fmt_date(val):
    if pd.isna(val) or val == "":
        return ""
    if isinstance(val, (pd.Timestamp, datetime)):
        return val.strftime("%m/%d/%Y")  #match example output
    return str(val)

def fmt_money(val):
    if pd.isna(val) or val == "":
        return ""
    try:
        return "${:,.2f}".format(float(val))
    except Exception:
        return str(val)

#replacement helpers (works even if placeholders split across runs)
def replace_in_paragraph(paragraph, replacements: dict[str, str]):
    if not paragraph.runs:
        return
    full_text = "".join(run.text for run in paragraph.runs)
    new_text = full_text
    for k, v in replacements.items():
        new_text = new_text.replace(k, v)
    if new_text != full_text:
        paragraph.runs[0].text = new_text
        for r in paragraph.runs[1:]:
            r.text = ""

def replace_in_container(container, replacements: dict[str, str]):
    for p in container.paragraphs:
        replace_in_paragraph(p, replacements)
    for table in container.tables:
        for row in table.rows:
            for cell in row.cells:
                replace_in_container(cell, replacements)

def replace_everywhere(doc: Document, replacements: dict[str, str]):
    #body
    replace_in_container(doc, replacements)
    #Headers/Footers
    for section in doc.sections:
        replace_in_container(section.header, replacements)
        replace_in_container(section.footer, replacements)
        for attr in ["first_page_header", "first_page_footer", "even_page_header", "even_page_footer"]:
            obj = getattr(section, attr, None)
            if obj is not None:
                replace_in_container(obj, replacements)

#load excel
df = pd.read_excel(EXCEL_PATH)

#first record = donor we are generating
first = df.iloc[0]

donor_id_col = "Constituent: Donor ID"
date_col = "Contact Report Date"
desc_col = "Contact Report: Description"
body_col = "Contact Report: Contact Report Body"

donor_id = first.get(donor_id_col, None)

#build [RECENT CONTACTS] block from all rows for this donor
contacts_df = df[df[donor_id_col] == donor_id].copy() if donor_id is not None else df.head(1).copy()

#sort by date (newest first) if available
if date_col in contacts_df.columns:
    contacts_df[date_col] = pd.to_datetime(contacts_df[date_col], errors="coerce")
    contacts_df = contacts_df.sort_values(by=date_col, ascending=False)

def build_contact_entry(r) -> str:
    desc = str(r.get(desc_col, "")).strip()
    date = fmt_date(r.get(date_col, ""))
    body = str(r.get(body_col, "")).strip()

    #skip empty rows cleanly
    if not (desc or body or date):
        return ""

    line1 = f"{desc} on {date}".strip()
    if line1 == "on":
        line1 = ""
    if body:
        return f"{line1}\n{body}".strip()
    return line1.strip()

entries = [build_contact_entry(r) for _, r in contacts_df.iterrows()]
entries = [e for e in entries if e]  # remove blanks

#most recent contact info (for the template's first line)
first_desc = ""
first_date = ""
first_body_plus_rest = ""

if entries:
    #use first row in sorted contacts_df for desc/date/body
    most_recent = contacts_df.iloc[0]
    first_desc = str(most_recent.get(desc_col, "")).strip()
    first_date = fmt_date(most_recent.get(date_col, ""))

    #put most recent BODY first, then append the rest
    most_recent_body = str(most_recent.get(body_col, "")).strip()
    rest_entries = entries[1:]  # remaining contacts (already "desc on date\nbody")

    first_body_plus_rest = most_recent_body.strip()
    if rest_entries:
        first_body_plus_rest = (first_body_plus_rest + "\n\n" + "\n\n".join(rest_entries)).strip()

#placeholder replacements
replacements = {
    "{{meeting_type}}": str(first.get("Contact Report: Contact Method", "")).strip(),
    "{{donor_name}}": str(first.get("Constituent: First and Last Name", "")).strip(),
    "{{staff_name}}": str(first.get("Contact Report: Contact Report Author (User): Full Name", "")).strip(),
    "{{meeting_platform}}": "Zoom Link",  # not in Excel
    "{{meeting_date}}": fmt_date(first.get("Contact Report Date", "")),
    "{{donor_affiliation}}": str(first.get("Constituent: Directory Suffix - NU School & Year", "")).strip(),
    "{{primary_employer}}": str(first.get("Constituent: Primary Employer: Account Name", "")).strip(),
    "{{donor_job_title}}": str(first.get("Constituent: Job Title", "")).strip(),
    "{{lifetime_giving}}": fmt_money(first.get("Constituent: Lifetime Fundraising", "")),
    "{{recent_gift_amount}}": fmt_money(first.get("Constituent: Amount of Most Recent Gift", "")),
    "{{recent_gift_date}}": fmt_date(first.get("Constituent: Date of Most Recent Gift", "")),

    #recent contacts (multi-row)
    "{{contact_report_description}}": first_desc,
    "{{contact_report_date}}": first_date,
    "{{recent_contacts}}": first_body_plus_rest,
}

#generate doc
doc = Document(TEMPLATE_PATH)
replace_everywhere(doc, replacements)
doc.save(OUTPUT_PATH)
print("Generated:", OUTPUT_PATH)
