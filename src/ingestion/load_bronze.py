"""Load the 9 raw Olist CSVs from a Unity Catalog volume into Delta bronze tables.

Runs as a spark_python_task (not a notebook_task) in the dbt_build job — a plain script avoids
the notebook-source-header sync race databricks-bundle-template's library files hit, since
there's no notebook conversion step involved.
"""

import sys

from pyspark.sql import SparkSession

# product_category_name_translation is small/static enough to live as a dbt seed instead —
# see dbt/seeds/product_category_name_translation.csv — so it's not loaded here.
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


def main(catalog_name: str, schema_name: str, raw_volume_path: str) -> None:
    spark = SparkSession.builder.getOrCreate()

    for bronze_name, filename in RAW_FILES.items():
        source_path = f"{raw_volume_path}/{filename}"
        target_table = f"{catalog_name}.{schema_name}.bronze_{bronze_name}"

        df = spark.read.option("header", "true").option("inferSchema", "true").csv(source_path)
        df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(target_table)
        print(f"Loaded {df.count()} rows into {target_table}")


if __name__ == "__main__":
    args = dict(arg.split("=", 1) for arg in sys.argv[1:])
    main(
        catalog_name=args["catalog_name"],
        schema_name=args["schema_name"],
        raw_volume_path=args["raw_volume_path"],
    )
