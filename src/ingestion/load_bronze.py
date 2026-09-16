# Databricks notebook source
# MAGIC %md
# MAGIC ### Load bronze: Olist raw CSVs -> Delta tables
# MAGIC Deployed as a `notebook_task`, matching `databricks-bundle-template`'s already-verified
# MAGIC pattern for plain `.py` notebook files under a DAB (`source: WORKSPACE`). `spark` and
# MAGIC `dbutils` are injected by the Databricks runtime, not imported.

# COMMAND ----------

dbutils.widgets.text("catalog_name", "")
dbutils.widgets.text("schema_name", "")
dbutils.widgets.text("raw_volume_path", "")

catalog_name = dbutils.widgets.get("catalog_name")
schema_name = dbutils.widgets.get("schema_name")
raw_volume_path = dbutils.widgets.get("raw_volume_path")

# COMMAND ----------

# product_category_name_translation is small/static enough to live as a dbt seed instead — see
# dbt/seeds/product_category_name_translation.csv — so it's not loaded here.
RAW_FILES = {
    "customers": "olist_customers_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
}

for bronze_name, filename in RAW_FILES.items():
    source_path = f"{raw_volume_path}/{filename}"
    target_table = f"{catalog_name}.{schema_name}.bronze_{bronze_name}"

    df = spark.read.option("header", "true").option("inferSchema", "true").csv(source_path)
    df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(target_table)
    print(f"Loaded {df.count()} rows into {target_table}")
