from pathlib import Path
import pandas as pd

# Read the original customer file from the project's data folder.
project_folder = Path(__file__).resolve().parent
possible_files = [
    project_folder / "data" / "raw" / "customers_raw.csv",
    project_folder / "data" / "customers_raw.csv",
    project_folder / "customers_raw.csv",
]

raw_file = None
for file in possible_files:
    if file.exists():
        raw_file = file
        break

if raw_file is None:
    raise FileNotFoundError(
        "Place customers_raw.csv inside data/raw or directly inside the data folder."
    )

customers = pd.read_csv(raw_file)
print("Rows in original file:", len(customers))

# Remove repeated customer records. Each customer should appear once.
customers = customers.drop_duplicates(subset="customer_id", keep="first").copy()

# Remove extra spaces and make category names consistent.
text_columns = [
    "gender", "contract_type", "internet_service", "payment_method",
    "autopay", "paperless_billing", "streaming_bundle", "churn"
]

for column in text_columns:
    customers[column] = customers[column].astype("string").str.strip()

# Fill missing total charges using monthly charges multiplied by tenure.
customers["total_charges"] = pd.to_numeric(
    customers["total_charges"], errors="coerce"
)
customers["total_charges"] = customers["total_charges"].fillna(
    customers["monthly_charges"] * customers["tenure_months"]
).round(2)

# The median support-ticket count is used for the missing values.
customers["support_tickets_90d"] = pd.to_numeric(
    customers["support_tickets_90d"], errors="coerce"
)
median_tickets = customers["support_tickets_90d"].median()
customers["support_tickets_90d"] = customers["support_tickets_90d"].fillna(
    median_tickets
).astype(int)

# Standardise the category values after removing extra spaces.
for column in text_columns:
    customers[column] = customers[column].str.lower().str.title()

# Keep the same spelling used in the source data and dashboard.
category_names = {
    "contract_type": {
        "Month-To-Month": "Month-to-month",
        "One Year": "One year",
        "Two Year": "Two year",
    },
    "internet_service": {
        "Dsl": "DSL",
        "Fiber Optic": "Fiber optic",
        "No Internet": "No internet",
    },
    "payment_method": {
        "Bank Transfer": "Bank transfer",
        "Credit Card": "Credit card",
        "Electronic Check": "Electronic check",
        "Mailed Check": "Mailed check",
    },
}

for column, names in category_names.items():
    customers[column] = customers[column].replace(names)

# Create tenure groups for the customer comparison.
customers["tenure_band"] = pd.cut(
    customers["tenure_months"],
    bins=[-1, 5, 11, 23, 47, float("inf")],
    labels=["0-5 months", "6-11 months", "12-23 months", "24-47 months", "48+ months"],
)

# Save the cleaned customer file next to the original data folder.
output_folder = project_folder / "analysis_output"
output_folder.mkdir(exist_ok=True)
customers.to_csv(output_folder / "customers_clean.csv", index=False)

# Overall customer and churn figures.
total_customers = customers["customer_id"].nunique()
churned_customers = (customers["churn"] == "Yes").sum()
retained_customers = total_customers - churned_customers
churn_rate = churned_customers / total_customers if total_customers else 0

print("\nCUSTOMER OVERVIEW")
print("Total customers:", total_customers)
print("Churned customers:", churned_customers)
print("Retained customers:", retained_customers)
print("Churn rate: {:.1%}".format(churn_rate))

# Compare churn across the main customer groups.
analysis_groups = [
    ("contract_type", "churn_by_contract.csv"),
    ("internet_service", "churn_by_internet_service.csv"),
    ("payment_method", "churn_by_payment_method.csv"),
    ("tenure_band", "churn_by_tenure.csv"),
    ("autopay", "churn_by_autopay.csv"),
]

for group_column, file_name in analysis_groups:
    result = customers.groupby(group_column, observed=True).agg(
        customers=("customer_id", "nunique"),
        churned=("churn", lambda values: (values == "Yes").sum()),
        average_monthly_charges=("monthly_charges", "mean"),
    ).reset_index()
    result["churn_rate"] = result["churned"] / result["customers"]
    result = result.sort_values("churn_rate", ascending=False)
    result.to_csv(output_folder / file_name, index=False)

    print("\nChurn by", group_column)
    print(result.to_string(index=False, formatters={"churn_rate": "{:.1%}".format}))

# Customers who have both a high monthly charge and recent support activity.
retention_list = customers[
    (customers["churn"] == "No") &
    (customers["support_tickets_90d"] >= 2)
].sort_values(
    ["monthly_charges", "support_tickets_90d"], ascending=[False, False]
)
retention_list.head(20).to_csv(
    output_folder / "customers_for_retention_review.csv", index=False
)

# Monthly charges linked to customers who have already churned.
revenue_at_risk = customers.loc[
    customers["churn"] == "Yes", "monthly_charges"
].sum()
print("\nMonthly charges from churned customers: {:.2f}".format(revenue_at_risk))
print("\nAnalysis files saved in:", output_folder)
