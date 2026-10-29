import json
from functools import reduce

from snowflake.snowpark.functions import col, count_distinct, current_timestamp, lit

DOCUMENTS = "FIN_COST_REPORTING.CORE.DOCUMENTS_ENRICHED"
RULESETS = "FIN_COST_REPORTING.CORE.RULESETS"
RESULT = "FIN_COST_REPORTING.CORE.DOCUMENT_COST_TYPES"

FIELDS = {
    "AccountNumber": "ACCOUNT_NUMBER",
    "OrgUnit": "ORG_UNIT",
    "ProfitCenter": "PROFIT_CENTER",
    "CostCenter": "COST_CENTER",
    "FundingSource": "FUNDING_SOURCE",
    "ExternalSupplier": "IS_EXTERNAL_SUPPLIER",
}

def one_value(column, value):
    """A true/false value, a text, or a text with * as wildcard (68* = starts with 68)."""
    if isinstance(value, bool):
        return col(column) == lit(value)
    text = str(value)
    if "*" in text:
        return col(column).like(text.replace("*", "%"))
    return col(column) == lit(text)


def rule_to_filter(rule):
    """JSON condition -> Snowpark filter. A list means any of; the fields of a rule must all hold."""
    conditions = []
    for field, value in rule.items():
        if field not in FIELDS:
            raise ValueError("unknown field '" + field + "', use one of: " + ", ".join(FIELDS))
        values = value if isinstance(value, list) else [value]
        conditions.append(reduce(lambda a, b: a | b, [one_value(FIELDS[field], v) for v in values]))
    if not conditions:
        raise ValueError("the rule is empty")
    return reduce(lambda a, b: a & b, conditions)


def check_one_ruleset_per_cost_type(rules):
    """Two rulesets with the same name (ignoring case and spaces) would label documents twice."""
    ids_by_name = {}
    for rule in rules:
        ids_by_name.setdefault(rule["NAME"].strip().upper(), []).append(str(rule["ID"]))
    twice = ["'" + name + "' (rulesets " + ", ".join(ids) + ")" for name, ids in ids_by_name.items() if len(ids) > 1]
    if twice:
        raise ValueError("a cost type can have only one ruleset: " + "; ".join(twice)
                         + ". Put the conditions in one rule, with a list for 'any of'.")


def classify(session):
    documents = session.table(DOCUMENTS)

    matches = []
    rules = session.table(RULESETS).collect()
    check_one_ruleset_per_cost_type(rules)
    for rule in rules:
        try:
            condition = rule_to_filter(json.loads(rule["RULE_DEFINITION"]))
        except Exception as error:
            raise ValueError("ruleset " + str(rule["ID"]) + " (" + rule["NAME"] + "): " + str(error))
        matches.append(documents.filter(condition).select(
            col("DOCUMENT_ID"), lit(rule["NAME"]).alias("COST_TYPE"), lit(rule["ID"]).alias("RULESET_ID")))

    if matches:
        reduce(lambda a, b: a.union_all(b), matches) \
            .with_column("CLASSIFIED_AT", current_timestamp()) \
            .write.mode("truncate").save_as_table(RESULT)
    else:
        session.table(RESULT).delete()

    per_document = session.table(RESULT).group_by("DOCUMENT_ID") \
        .agg(count_distinct(col("COST_TYPE")).alias("COST_TYPES"))
    documents_total = documents.count()
    with_cost_type = per_document.count()
    with_several = per_document.filter(col("COST_TYPES") > 1).count()
    return {
        "rulesets": len(rules),
        "documents": documents_total,
        "with_one_cost_type": with_cost_type - with_several,
        "with_several_cost_types": with_several,
        "without_cost_type": documents_total - with_cost_type,
    }
