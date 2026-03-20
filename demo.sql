-- =========================================================================
-- Демонстрационный скрипт: pg_llm_utils (SQL-интеграция с LLM и RAG)
-- База данных: Olist E-commerce Dataset
-- =========================================================================

-- 1. Активация расширений
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS plpython3u;
DROP EXTENSION IF EXISTS pg_llm_utils CASCADE;
CREATE EXTENSION pg_llm_utils;

-- 2. Проверка таблиц и базовой статистики Olist (Подтверждение загрузки данных)
SELECT count(*) AS total_reviews FROM olist_order_reviews;
SELECT count(*) AS empty_reviews FROM olist_order_reviews WHERE review_comment_message IS NULL;

-- 3. ДЕМОНСТРАЦИЯ ФУНКЦИИ 1: Семантическое кэширование и прямой запрос к LLM
-- Выполняем задачу: Перевод и саммаризация сложного бразильского отзыва на лету
-- Первый запуск (выполняет API-вызов к Groq - Llama-3)
SELECT 
    review_score, 
    review_comment_message AS original_portuguese,
    groq_chat('You are an expert. Please translate to Russian and extract the main problem: ' || review_comment_message) AS ai_analysis
FROM olist_order_reviews 
WHERE review_score = 1 AND review_comment_message IS NOT NULL 
LIMIT 1;

-- Выполняем тот же запрос повторно:
-- (Обратите внимание на NOTICE в консоли базы данных: "Groq API: Результат взят из кэша...")
SELECT 
    review_score, 
    review_comment_message AS original_portuguese,
    groq_chat('You are an expert. Please translate to Russian and extract the main problem: ' || review_comment_message) AS ai_analysis
FROM olist_order_reviews 
WHERE review_score = 1 AND review_comment_message IS NOT NULL 
LIMIT 1;

-- Просмотр таблицы кэша:
SELECT prompt_hash, model_name, left(response, 50) || '...' as cached_response, created_at FROM llm_cache;

-- 4. ДЕМОНСТРАЦИЯ ФУНКЦИИ 2: Генерация эмбеддингов локально в RAM PostgreSQL (sentence-transformers)
-- Первая генерация подгрузит модель 'paraphrase-multilingual-MiniLM-L12-v2' в оперативную память
SELECT generate_embedding('Где моя посылка? Доставка задерживается.') AS vector_example;

-- 5. ДЕМОНСТРАЦИЯ ФУНКЦИИ 3: RAG (Retrieval-Augmented Generation) и Векторный Поиск (pgvector)
-- Векторизуем 500 случайных текстовых отзывов из датасета (займет 1-2 минуты в зависимости от CPU)
CALL vectorize_reviews(500);

-- Проверяем, что отзывы векторизовались
SELECT count(*) as total_vectors FROM review_embeddings;

-- Задаем естественный вопрос на русском языке к бразильской базе.
-- Наша функция:
-- 1. Сгенерирует вектор для вопроса (RU).
-- 2. Найдет через pgvector <=> ближайшие отзывы по смыслу (PT).
-- 3. Сформирует промпт с контекстом.
-- 4. Получит ответ от Groq LLM.
SELECT ask_olist('На что чаще всего жалуются клиенты, если поставить низкую оценку? Дай развернутый ответ.');

SELECT ask_olist('Какие самые приятные слова пишут пользователи при высоких оценках доставки?');