import io
import json

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import col, parse_json

st.set_page_config(page_title="Finance cost reporting", layout="wide")
session = get_active_session()

# Fields a rule may use (the same as in the classification procedure)
RULE_FIELDS = {"AccountNumber", "OrgUnit", "ProfitCenter", "CostCenter", "FundingSource", "ExternalSupplier"}
UNCLASSIFIED = "Unclassified"
SEVERAL = "Several cost types"


def euro(value):
    return f"€{value:,.2f}"


# =============================================================================
# Data (read once, kept for five minutes)
# =============================================================================

@st.cache_data(ttl=300, show_spinner="Loading the documents ...")
def load_documents():
    df = session.table("CORE.V_DOCUMENTS_CLASSIFIED").select(
        "DOCUMENT_ID", "FISCAL_YEAR", "BOOKING_PERIOD", "PERIOD_LABEL", "ACCOUNT_NUMBER",
        "COST_CENTER", "COST_CENTER_NAME", "ORG_UNIT", "FUNDING_SOURCE", "SUPPLIER_NAME",
        "AMOUNT", "COST_TYPE", "COST_TYPE_COUNT", "DOCUMENT_DETAILS").to_pandas()
    df["AMOUNT"] = df["AMOUNT"].astype(float)
    return df


def load_rules():
    return session.table("CORE.RULESETS") \
        .select("ID", "NAME", col("RULE_DEFINITION").cast("string").alias("RULE_DEFINITION")) \
        .sort("ID").to_pandas()


# =============================================================================
# Page 1: cost overview
# =============================================================================

def overview():
    st.title("Cost overview")
    st.caption("Costs from the SAP documents, classified into cost types with the rules of the finance controllers.")

    df = load_documents()
    if df.empty:
        st.warning("There are no documents yet. Run the refresh (Exercise 3) first.")
        return

    # Filters
    years = sorted(df["FISCAL_YEAR"].unique(), reverse=True)
    year = st.sidebar.selectbox("Fiscal year", years)
    first, last = st.sidebar.slider("Booking periods", 1, 12, (1, 12))
    org_units = st.sidebar.multiselect("Org unit", sorted(df["ORG_UNIT"].unique()))
    cost_types = st.sidebar.multiselect("Cost type", sorted(df["COST_TYPE"].unique()))
    funding = st.sidebar.multiselect("Funding source", sorted(df["FUNDING_SOURCE"].unique()))

    selected = df[(df["FISCAL_YEAR"] == year) & df["BOOKING_PERIOD"].between(first, last)]
    if org_units:
        selected = selected[selected["ORG_UNIT"].isin(org_units)]
    if cost_types:
        selected = selected[selected["COST_TYPE"].isin(cost_types)]
    if funding:
        selected = selected[selected["FUNDING_SOURCE"].isin(funding)]

    if selected.empty:
        st.info("No documents match these filters. Widen the periods or clear a filter.")
        return

    # KPIs
    total = selected["AMOUNT"].sum()
    to_review = selected[selected["COST_TYPE_COUNT"] != 1]
    classified = selected[selected["COST_TYPE_COUNT"] == 1]["AMOUNT"].sum()
    previous = df[(df["FISCAL_YEAR"] == year - 1) & df["BOOKING_PERIOD"].between(first, last)]["AMOUNT"].sum()

    k1, k2, k3 = st.columns(3)
    k1.metric("Total cost", euro(total),
              delta=f"{(total / previous - 1) * 100:+.1f}% vs {year - 1}" if previous else None,
              delta_color="inverse")
    k2.metric("Classified with one cost type", f"{100 * classified / total:.1f}%" if total else "-")
    k3.metric("Documents to review", f"{len(to_review):,}",
              help="Documents with no cost type, or with several.")

    # Chart: cost per period and cost type
    st.subheader("Cost per period and cost type")
    chart = selected.groupby(["PERIOD_LABEL", "COST_TYPE"], as_index=False)["AMOUNT"].sum()
    st.bar_chart(chart, x="PERIOD_LABEL", y="AMOUNT", color="COST_TYPE")

    # Cost type table
    st.subheader("Cost types")
    by_type = selected.groupby("COST_TYPE", as_index=False).agg(DOCUMENTS=("DOCUMENT_ID", "count"), AMOUNT=("AMOUNT", "sum"))
    by_type["SHARE_PCT"] = 100 * by_type["AMOUNT"] / total
    st.dataframe(by_type.sort_values("AMOUNT", ascending=False), hide_index=True, use_container_width=True,
                 column_config={"COST_TYPE": "Cost type", "DOCUMENTS": "Documents",
                                "AMOUNT": st.column_config.NumberColumn("Amount (EUR)", format="%.2f"),
                                "SHARE_PCT": st.column_config.NumberColumn("Share (%)", format="%.1f")})

    # Documents, with a flag for those that need attention
    st.subheader("Documents")
    only_review = st.checkbox("Only documents to review (no cost type, or several)")
    table = to_review if only_review else selected
    st.dataframe(table.sort_values("AMOUNT", ascending=False)[
        ["DOCUMENT_ID", "PERIOD_LABEL", "ACCOUNT_NUMBER", "COST_CENTER_NAME", "ORG_UNIT", "SUPPLIER_NAME", "AMOUNT",
         "COST_TYPE", "DOCUMENT_DETAILS"]],
        hide_index=True, use_container_width=True,
        column_config={"DOCUMENT_ID": "Document", "PERIOD_LABEL": "Period", "ACCOUNT_NUMBER": "Account",
                       "COST_CENTER_NAME": "Cost center", "ORG_UNIT": "Org unit", "SUPPLIER_NAME": "Supplier",
                       "AMOUNT": st.column_config.NumberColumn("Amount (EUR)", format="%.2f"),
                       "COST_TYPE": "Cost type", "DOCUMENT_DETAILS": "Details"})
    st.download_button("Download these documents (CSV)", table.to_csv(index=False).encode("utf-8"),
                       file_name=f"documents_{year}.csv", mime="text/csv", disabled=table.empty)

    # Drill-down: why does a document have its cost type?
    st.subheader("Inspect a document")
    document_id = st.selectbox("Document", [""] + table["DOCUMENT_ID"].tolist())
    if document_id:
        row = selected[selected["DOCUMENT_ID"] == document_id].iloc[0]
        left, right = st.columns(2)
        left.write(f"**{row['DOCUMENT_DETAILS']}**  \n{row['PERIOD_LABEL']} · account {row['ACCOUNT_NUMBER']} · "
                   f"{row['COST_CENTER_NAME']} · {row['SUPPLIER_NAME']} · {euro(row['AMOUNT'])}")
        found = session.table("CORE.DOCUMENT_COST_TYPES").filter(col("DOCUMENT_ID") == document_id)
        rulesets = session.table("CORE.RULESETS")
        matches = found.join(rulesets, found["RULESET_ID"] == rulesets["ID"], "left") \
            .select(found["COST_TYPE"], found["RULESET_ID"],
                    rulesets["RULE_DEFINITION"].cast("string").alias("RULE_DEFINITION")).to_pandas()
        if matches.empty:
            right.warning("No ruleset matches this document, so it is shown as Unclassified.")
        else:
            right.write("Matching rulesets:")
            right.dataframe(matches, hide_index=True, use_container_width=True)
            if matches["COST_TYPE"].nunique() > 1:
                right.warning("Rulesets with different cost types match this document: it must be resolved.")


# =============================================================================
# Page 2: rules
# =============================================================================

def check_rules(rules):
    """Returns a list of problems found in an uploaded table of rules (empty = fine)."""
    problems = []
    missing = {"ID", "NAME", "RULE_DEFINITION"} - set(rules.columns)
    if missing:
        return ["The sheet needs the columns ID, NAME and RULE_DEFINITION; missing: " + ", ".join(sorted(missing))]
    if rules.empty:
        return ["The sheet has no rules."]
    for position, row in rules.iterrows():
        label = f"Row {position + 2}"
        try:
            int(row["ID"])
        except (TypeError, ValueError):
            problems.append(f"{label}: ID must be a whole number")
        if pd.isna(row["NAME"]) or not str(row["NAME"]).strip():
            problems.append(f"{label}: NAME is empty")
        try:
            definition = json.loads(str(row["RULE_DEFINITION"]))
        except ValueError:
            problems.append(f"{label}: RULE_DEFINITION is not valid JSON")
            continue
        if not isinstance(definition, dict) or not definition:
            problems.append(f"{label}: RULE_DEFINITION must be a JSON object such as {{\"AccountNumber\": \"68*\"}}")
            continue
        for field, value in definition.items():
            if field not in RULE_FIELDS:
                problems.append(f"{label}: unknown field '{field}', use one of: {', '.join(sorted(RULE_FIELDS))}")
            elif field == "ExternalSupplier" and not isinstance(value, bool):
                problems.append(f"{label}: ExternalSupplier must be true or false")
    if rules["ID"].duplicated().any():
        problems.append("The sheet uses the same ID more than once")
    names = rules["NAME"].dropna().astype(str).str.strip().str.upper()
    twice = sorted(set(names[names.duplicated()]))
    if twice:
        problems.append("A cost type can have only one rule, but these have several: " + ", ".join(twice)
                        + ". Put the conditions in one rule, with a list for 'any of'.")
    return problems


def rules_page():
    st.title("Rules")
    st.caption("Each rule gives a cost type to the documents that match its condition. "
               "Conditions: AccountNumber, OrgUnit, ProfitCenter, CostCenter, FundingSource (text, * as wildcard, "
               "a list means any of) and ExternalSupplier (true or false).")

    current = load_rules()
    st.dataframe(current, hide_index=True, use_container_width=True)

    template = io.BytesIO()
    current.to_excel(template, index=False)
    st.download_button("Download the rules as Excel", template.getvalue(), file_name="rules.xlsx",
                       mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    st.subheader("Upload changed rules")
    st.write("The uploaded rules replace all current rules.")
    uploaded = st.file_uploader("Excel file (.xlsx) with the columns ID, NAME, RULE_DEFINITION", type=["xlsx"])
    if uploaded is None:
        return
    try:
        rules = pd.read_excel(uploaded, dtype=object)
    except Exception:
        st.error("The file could not be read. Download the rules above, change them in Excel and upload that file.")
        return
    rules.columns = [str(c).strip().upper() for c in rules.columns]
    problems = check_rules(rules)
    if problems:
        st.error("The file was not used. Fix these and upload it again:")
        for problem in problems:
            st.write("- " + problem)
        return

    st.success(f"{len(rules)} rules are valid.")
    st.dataframe(rules, hide_index=True, use_container_width=True)
    if st.button("Replace the rules and classify again", type="primary"):
        new_rules = session.create_dataframe(
            [(int(r.ID), str(r.NAME).strip(), str(r.RULE_DEFINITION)) for r in rules.itertuples()],
            schema=["ID", "NAME", "RULE_DEFINITION"])
        try:      # "truncate" replaces all rows in one statement, so the rules are never half-replaced
            new_rules.select(col("ID"), col("NAME"), parse_json(col("RULE_DEFINITION")).alias("RULE_DEFINITION")) \
                .write.mode("truncate").save_as_table("CORE.RULESETS")
        except Exception as error:
            st.error(f"The rules were not changed: {error}")
            return
        try:
            result = session.call("CORE.SP_CLASSIFY_DOCUMENTS")
        except Exception as error:
            st.error(f"The rules were saved, but the classification failed: {error}")
            return
        st.cache_data.clear()
        st.success("Rules saved and documents classified.")
        st.json(json.loads(result) if isinstance(result, str) else result)


# =============================================================================
# Navigation
# =============================================================================

page = st.sidebar.radio("Page", ["Cost overview", "Rules"])
st.sidebar.divider()

if page == "Cost overview":
    overview()
else:
    rules_page()
