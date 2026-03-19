# clean_olist_duplicates.py
"""
Скрипт для удаления дубликатов из файлов Olist Brazilian E-Commerce Dataset.
Удаляет полные дубликаты строк + дубликаты по основным ключевым полям.
"""

from pathlib import Path

import pandas as pd

# Путь к папке с данными
DATA_DIR = Path("data")
DATA_DIR.mkdir(exist_ok=True)

# Список всех файлов Olist
FILES = [
    "olist_customers_dataset.csv",
    "olist_geolocation_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_orders_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]

# По каким колонкам удалять дубликаты (кроме полных дубликатов строк)
# Если колонка не указана — удаляются только полные дубликаты
UNIQUE_KEYS = {
    "olist_customers_dataset.csv": ["customer_id"],
    "olist_geolocation_dataset.csv": [
        "geolocation_zip_code_prefix",
        "geolocation_city",
        "geolocation_state",
    ],
    "olist_order_items_dataset.csv": ["order_id", "order_item_id"],
    "olist_order_payments_dataset.csv": ["order_id", "payment_sequential"],
    "olist_order_reviews_dataset.csv": ["review_id"],
    "olist_orders_dataset.csv": ["order_id"],
    "olist_products_dataset.csv": ["product_id"],
    "olist_sellers_dataset.csv": ["seller_id"],
    "product_category_name_translation.csv": ["product_category_name"],
}


def clean_file(filename: str):
    filepath = DATA_DIR / filename

    if not filepath.exists():
        print(f"Файл не найден: {filepath}")
        return

    print(f"\nОбработка: {filename}")

    # Читаем файл
    try:
        df = pd.read_csv(filepath, low_memory=False)
    except Exception as e:
        print(f"Ошибка чтения {filename}: {e}")
        return

    original_rows = len(df)
    print(f"  Исходное количество строк: {original_rows:,}")

    # 1. Удаляем полные дубликаты строк
    df = df.drop_duplicates()
    after_full_dup = len(df)

    # 2. Удаляем дубликаты по ключевым полям (если указаны)
    key_cols = UNIQUE_KEYS.get(filename, [])
    if key_cols:
        before_key_dup = len(df)
        df = df.drop_duplicates(subset=key_cols, keep="first")
        after_key_dup = len(df)
        print(f"  После удаления полных дубликатов: {after_full_dup:,}")
        print(
            f"  После удаления дубликатов по {key_cols}: {after_key_dup:,} (удалено {before_key_dup - after_key_dup:,} строк)"
        )
    else:
        print(f"  После удаления полных дубликатов: {after_full_dup:,}")

    # Сохраняем очищенный файл
    cleaned_path = DATA_DIR / f"{Path(filename).stem}.csv"
    df.to_csv(cleaned_path, index=False, encoding="utf-8")
    print(f"  Сохранено: {cleaned_path} ({len(df):,} строк)")


def main():
    print("Очистка дубликатов в датасете Olist...")
    print(f"Папка данных: {DATA_DIR.resolve()}\n")

    for filename in FILES:
        clean_file(filename)

    print("\nГотово!")


if __name__ == "__main__":
    main()
