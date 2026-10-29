Finance controllers receive thousands of accounting line items synced daily from SAP. To report
costs by management category (e.g. Wages & Salaries, EU Funded Projects, Maintenance, etc.),
they map the document by hand in Excel, using their own rules. This is slow and inconsistent, and
it’s hard to verify the output. Data problems such as duplicate postings or cost centers missing
from organization hierarchy surface only at month-end close.

Solution - Snowflake native pipeline that:
- Starts from the SAP documents in Snowflake (synthetic data)
- Turns them into a cleansed, enriched reporting dataset that refreshes daily, with validation
before anything is published
- Classifies every line item into a cost type using rules that controllers maintain themselves,
uploaded from Excel, so a rule change needs no code change
- Presents the result in a Streamlit app with filters, drill-down to single documents, a data-quality
work list and an admin page for the rules.
