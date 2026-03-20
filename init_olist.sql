-- =====================================================================
-- init_olist.sql

-- =====================================================================
-- Включаем расширение vector (если ещё не включено через preload)
CREATE EXTENSION IF NOT EXISTS vector;

-- Таблица 1: Клиенты
-- Содержит информацию о покупателях (каждый заказ имеет уникального клиента)
CREATE TABLE IF NOT EXISTS olist_customers (
    customer_id                 VARCHAR(32) PRIMARY KEY,          -- Уникальный ID клиента для конкретного заказа
    customer_unique_id          VARCHAR(32) NOT NULL,             -- Постоянный ID клиента (один человек может иметь много заказов)
    customer_zip_code_prefix    INTEGER,                          -- Первые 5 цифр почтового индекса
    customer_city               VARCHAR(100),                    -- Город клиента
    customer_state              CHAR(2)                           -- Штат (UF) в Бразилии, например SP, RJ, MG
);

COMMENT ON TABLE olist_customers IS 'Информация о покупателях. Каждый заказ привязан к уникальному customer_id, но один и тот же человек может иметь несколько заказов под разными customer_id (customer_unique_id — постоянный идентификатор человека).';

-- Таблица 2: Геолокация по почтовым индексам
-- Справочник широты/долготы для бразильских почтовых индексов
CREATE TABLE IF NOT EXISTS olist_geolocation (
    geolocation_zip_code_prefix INTEGER,                          -- Первые 5 цифр почтового индекса
    geolocation_lat             DOUBLE PRECISION,                 -- Широта
    geolocation_lng             DOUBLE PRECISION,                 -- Долгота
    geolocation_city            VARCHAR(100),                    -- Город
    geolocation_state           CHAR(2)                           -- Штат
);

COMMENT ON TABLE olist_geolocation IS 'Справочник координат по почтовым индексам Бразилии. Используется для гео-анализа и расчёта расстояний.';

-- Таблица 3: Позиции в заказах (товары в заказе)
-- Каждая строка — один товар в заказе (заказ может содержать несколько товаров)
CREATE TABLE IF NOT EXISTS olist_order_items (
    order_id                    VARCHAR(32),                      -- ID заказа
    order_item_id               SMALLINT,                         -- Порядковый номер товара в заказе (1, 2, 3...)
    product_id                  VARCHAR(32),                      -- ID товара
    seller_id                   VARCHAR(32),                      -- ID продавца
    shipping_limit_date         TIMESTAMP,                        -- Крайний срок передачи товара перевозчику
    price                       NUMERIC(10,2),                    -- Цена товара
    freight_value               NUMERIC(10,2),                    -- Стоимость доставки этого товара
    PRIMARY KEY (order_id, order_item_id)
);

COMMENT ON TABLE olist_order_items IS 'Каждая строка — один товар в заказе. Заказ может содержать несколько строк (несколько товаров). Здесь хранятся цены и стоимость доставки для каждого товара.';

-- Таблица 4: Платежи по заказам
-- Информация об оплате (заказ может быть оплачен частями или разными способами)
CREATE TABLE IF NOT EXISTS olist_order_payments (
    order_id                    VARCHAR(32),
    payment_sequential          SMALLINT,                         -- Порядковый номер платежа (если несколько)
    payment_type                VARCHAR(20),                      -- Тип оплаты: credit_card, boleto, voucher, debit_card и т.д.
    payment_installments        SMALLINT,                         -- Количество рассрочек/взносов
    payment_value               NUMERIC(10,2),                    -- Сумма этого платежа
    PRIMARY KEY (order_id, payment_sequential)
);

COMMENT ON TABLE olist_order_payments IS 'Информация об оплатах заказа. Один заказ может иметь несколько платежей (рассрочка, разные способы оплаты).';

-- Таблица 5: Отзывы покупателей
-- Самая важная таблица для RAG и анализа настроений
CREATE TABLE IF NOT EXISTS olist_order_reviews (
    review_id                   VARCHAR(32) PRIMARY KEY,          -- Уникальный ID отзыва
    order_id                    VARCHAR(32),                      -- Связанный заказ
    review_score                SMALLINT,                         -- Оценка от 1 до 5
    review_comment_title        TEXT,                             -- Заголовок отзыва (часто короткий или пустой)
    review_comment_message      TEXT,                             -- Текст отзыва (самое ценное для LLM)
    review_creation_date        TIMESTAMP,                        -- Дата создания отзыва
    review_answer_timestamp     TIMESTAMP                         -- Дата ответа продавца (если был)
);

COMMENT ON TABLE olist_order_reviews IS 'Отзывы покупателей о заказах. Основной источник текстов для анализа тональности, RAG и векторного поиска по отзывам.';

-- Таблица 6: Заказы (основная таблица фактов)
-- Статусы и временные метки всего жизненного цикла заказа
CREATE TABLE IF NOT EXISTS olist_orders (
    order_id                    VARCHAR(32) PRIMARY KEY,
    customer_id                 VARCHAR(32),                      -- Покупатель
    order_status                VARCHAR(20),                      -- Статус: delivered, shipped, canceled, invoiced и т.д.
    order_purchase_timestamp    TIMESTAMP,                        -- Дата и время создания заказа
    order_approved_at           TIMESTAMP,                        -- Дата подтверждения оплаты
    order_delivered_carrier_at  TIMESTAMP,                        -- Дата передачи перевозчику
    order_delivered_customer_at TIMESTAMP,                        -- Дата доставки клиенту
    order_estimated_delivery_date TIMESTAMP                       -- Планируемая дата доставки
);

COMMENT ON TABLE olist_orders IS 'Основная таблица заказов: статусы, даты создания, оплаты, доставки и планируемой доставки. Центральная точка для соединения всех данных.';

-- Таблица 7: Товары (продукты)
-- Справочник всех продаваемых товаров
CREATE TABLE IF NOT EXISTS olist_products (
    product_id                  VARCHAR(32) PRIMARY KEY,
    product_category_name       VARCHAR(100),                     -- Название категории на португальском
    product_name_lenght         NUMERIC,                         -- Длина названия товара (в символах)
    product_description_lenght  NUMERIC,                         -- Длина описания (в символах)
    product_photos_qty          NUMERIC,                         -- Количество фотографий товара
    product_weight_g            NUMERIC,                          -- Вес в граммах
    product_length_cm           NUMERIC,                         -- Длина в см
    product_height_cm           NUMERIC,                         -- Высота в см
    product_width_cm            NUMERIC                          -- Ширина в см
);

COMMENT ON TABLE olist_products IS 'Справочник товаров: категории, размеры, вес, количество фото и длина описания/названия.';

-- Таблица 8: Продавцы
-- Информация о продавцах (магазинах) на платформе
CREATE TABLE IF NOT EXISTS olist_sellers (
    seller_id                   VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix      INTEGER,                          -- Первые 5 цифр почтового индекса продавца
    seller_city                 VARCHAR(100),                     -- Город продавца
    seller_state                CHAR(2)                           -- Штат продавца
);

COMMENT ON TABLE olist_sellers IS 'Информация о продавцах (магазинах) на маркетплейсе Olist.';

-- Таблица 9: Перевод категорий товаров на английский
-- Очень полезно для анализа и RAG (чтобы не работать с португальскими названиями)
CREATE TABLE IF NOT EXISTS product_category_name_translation (
    product_category_name            VARCHAR(100) PRIMARY KEY,    -- Категория на португальском
    product_category_name_english    VARCHAR(100)                  -- Категория на английском (например 'bed_bath_table')
);

COMMENT ON TABLE product_category_name_translation IS 'Перевод названий категорий товаров с португальского на английский. Очень полезно для анализа и отображения результатов на английском/русском.';

-- =====================================================================
-- Загрузка данных из CSV-файлов
-- =====================================================================

\COPY olist_customers                 FROM '/tmp/olist_data/olist_customers_dataset.csv'                 WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');
\COPY olist_geolocation               FROM '/tmp/olist_data/olist_geolocation_dataset.csv'               WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');
\COPY olist_order_items               FROM '/tmp/olist_data/olist_order_items_dataset.csv'               WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');
\COPY olist_order_payments            FROM '/tmp/olist_data/olist_order_payments_dataset.csv'            WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');
\COPY olist_order_reviews             FROM '/tmp/olist_data/olist_order_reviews_dataset.csv'             WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');
\COPY olist_orders                    FROM '/tmp/olist_data/olist_orders_dataset.csv'                    WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');
\COPY olist_products                  FROM '/tmp/olist_data/olist_products_dataset.csv'                  WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');
\COPY olist_sellers                   FROM '/tmp/olist_data/olist_sellers_dataset.csv'                   WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');
\COPY product_category_name_translation FROM '/tmp/olist_data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');

-- =====================================================================
-- Полезные индексы для ускорения запросов
-- =====================================================================

CREATE INDEX IF NOT EXISTS idx_orders_customer_id     ON olist_orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id   ON olist_order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON olist_order_items (product_id);
CREATE INDEX IF NOT EXISTS idx_reviews_order_id       ON olist_order_reviews (order_id);
CREATE INDEX IF NOT EXISTS idx_products_category      ON olist_products (product_category_name);
