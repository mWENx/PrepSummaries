import pandas as pd
from docx import Document
from datetime import datetime
import os
from dotenv import load_dotenv
from openai import OpenAI
import json 
import re

########################################################################
# setup 

# ChatGPT set up 
load_dotenv()

CHATGPT_API_KEY = os.getenv("ChatGPT_API_KEY")
if not CHATGPT_API_KEY:
    raise ValueError("Missing ChatGPT_API_KEY in .env")

client = OpenAI(api_key=CHATGPT_API_KEY)

# Local file paths set up 

EXCEL_PATH = "Briefing Data Pull Example.xlsx"
TEMPLATE_PATH = "Briefing_Template.docx"
OUTPUT_PATH = "Generated_Briefing.docx"

########################################################################
# functions 

# ChatGPT queryer 
def query_chatgpt(query: str, model: str = "gpt-4.1-mini") -> str:
    response = client.responses.create(
        model=model,
        input=query,
    )
    return response.output_text.strip()

def parse_chatgpt_json(text: str) -> dict:
    cleaned = (text or "").strip()
    if not cleaned:
        raise ValueError("ChatGPT returned empty output_text (expected JSON).")

    # Handle ```json ... ``` wrappers.
    if cleaned.startswith("```"):
        lines = cleaned.splitlines()
        if lines:
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines).strip()

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        # Fallback: extract first JSON object when model includes extra prose.
        match = re.search(r"\{[\s\S]*\}", cleaned)
        if not match:
            preview = cleaned[:300].replace("\n", "\\n")
            raise ValueError(f"ChatGPT output is not valid JSON. Preview: {preview}")
        return json.loads(match.group(0))

# formatters
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

# replacement helpers (works even if placeholders split across runs)
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
                
# helper to add bullet points 
def insert_bio_notes(doc: Document, notes: list[str]):
    has_list_bullet = any(style.name == "ListBullet" for style in doc.styles)

    for paragraph in doc.paragraphs:
        if "{{bio_notes}}" in paragraph.text:
            parent = paragraph._element.getparent()
            idx = parent.index(paragraph._element)

            # remove the placeholder paragraph
            parent.remove(paragraph._element)

            # insert each note as a bullet paragraph
            for i, note in enumerate(notes):
                new_p = doc.add_paragraph(note)
                if has_list_bullet:
                    new_p.style = "ListBullet"
                else:
                    new_p.text = f"- {note}"
                parent.insert(idx + i, new_p._element)
            break

#load excel
df = pd.read_excel(EXCEL_PATH)

#first record = donor we are generating
# does this need to be updated in the future? 
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

# extract and store user info 
donor_affil = str(first.get("Constituent: Directory Suffix - NU School & Year", "")).strip()
donor_employer = str(first.get("Constituent: Primary Employer: Account Name", "")).strip()
donor_job = str(first.get("Constituent: Job Title", "")).strip()
donor_name = str(first.get("Constituent: First and Last Name", "")).strip()


#placeholder replacements
replacements = {
    "{{meeting_type}}": str(first.get("Contact Report: Contact Method", "")).strip(),
    "{{donor_name}}": donor_name,
    "{{staff_name}}": str(first.get("Contact Report: Contact Report Author (User): Full Name", "")).strip(),
    "{{meeting_platform}}": "Zoom Link",  # not in Excel
    "{{meeting_date}}": fmt_date(first.get("Contact Report Date", "")),
    "{{donor_affiliation}}": donor_affil,
    "{{primary_employer}}": donor_employer,
    "{{donor_job_title}}": donor_job,
    "{{lifetime_giving}}": fmt_money(first.get("Constituent: Lifetime Fundraising", "")),
    "{{recent_gift_amount}}": fmt_money(first.get("Constituent: Amount of Most Recent Gift", "")),
    "{{recent_gift_date}}": fmt_date(first.get("Constituent: Date of Most Recent Gift", "")),

    #recent contacts (multi-row)
    "{{contact_report_description}}": first_desc,
    "{{contact_report_date}}": first_date,
    "{{recent_contacts}}": first_body_plus_rest,
}

# Google search / web scraping 

search_str = f"{donor_name}, {donor_employer}"

summary_prompt = f"""
Search the web for {donor_name}.

Only use:
- company websites
- LinkedIn
- other reputable sources 

Verify identity by confirming:
- worked as {donor_job} at {donor_employer} 
- affiliated with Northwestern University

Return ONLY valid JSON with this schema:

{{
  "found": boolean,
  "biography": [string],
  "sources": [string]
}}

The strings in "biography" should follow this general order: 
1st string: current position, how long it's been, and primary responsibilities 
2nd to Nth string: previous positions, likewise include length of term and primary responsibilities. Can split into multiple strings if extensive. 
(N+1)th string: Educational background 
(N+2)th string: where they are currently based if the info is available
Last string: any personal notes, like who they're married to 

DO NOT include any text outside the JSON.
"""

chatgpt_summary = query_chatgpt(summary_prompt)
# print(chatgpt_summary)

# parse output 
data = parse_chatgpt_json(chatgpt_summary)
bio_notes = data.get("biography", [])
if not isinstance(bio_notes, list):
    raise ValueError("Expected JSON field 'biography' to be a list.")
      
#generate doc
doc = Document(TEMPLATE_PATH)
insert_bio_notes(doc, bio_notes)
replace_everywhere(doc, replacements)
doc.save(OUTPUT_PATH)
print("Generated:", OUTPUT_PATH)
