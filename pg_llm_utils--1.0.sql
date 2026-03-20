-- Запрещаем выполнение скрипта вне процесса установки расширения
\echo Use "CREATE EXTENSION pg_llm_utils" to load this file. \quit

-- Таблица для кэширования запросов
CREATE TABLE IF NOT EXISTS llm_cache (
    id SERIAL PRIMARY KEY,
    prompt_hash TEXT UNIQUE NOT NULL,
    model_name TEXT NOT NULL,
    response TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица для возможных настроек (на будущее)
CREATE TABLE IF NOT EXISTS llm_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Тестовая функция для проверки Python-окружения и доступа к ключу
CREATE OR REPLACE FUNCTION test_groq_connection()
RETURNS text
LANGUAGE plpython3u
AS $$
    import os
    import sys
    
    try:
        import requests
        import groq
    except ImportError as e:
        return f"Ошибка импорта библиотек: {e}"

    api_key = os.environ.get('GROQ_API_KEY')
    
    if not api_key:
        return "Библиотеки установлены успешно, но GROQ_API_KEY не найден в переменных окружения."
        
    # Скрываем часть ключа для безопасности
    masked_key = f"{api_key[:4]}...{api_key[-4:]}" if len(api_key) > 8 else "***"
    
    return f"Успех! Python: {sys.version.split()[0]}, Groq SDK доступен. Ключ: {masked_key}"
$$;


-- Основная функция для генерации текста через Groq API
CREATE OR REPLACE FUNCTION groq_chat(prompt TEXT, model_name TEXT DEFAULT 'llama-3.1-8b-instant')
RETURNS TEXT
LANGUAGE plpython3u
AS $$
    import os
    import hashlib
    import plpy
    
    try:
        from groq import Groq
    except ImportError:
        plpy.error("Библиотека groq не найдена. Убедитесь, что она установлена.")

    api_key = os.environ.get('GROQ_API_KEY')
    if not api_key:
        plpy.error("Переменная окружения GROQ_API_KEY не задана.")

    cache_string = model_name + prompt
    prompt_hash = hashlib.md5(cache_string.encode('utf-8')).hexdigest()

    plan = plpy.prepare("SELECT response FROM llm_cache WHERE prompt_hash = $1 AND model_name = $2 LIMIT 1",["text", "text"])
    rv = plpy.execute(plan,[prompt_hash, model_name])
    
    if len(rv) > 0:
        plpy.notice(f"Groq API: Результат взят из кэша (хэш: {prompt_hash[:8]})")
        return rv[0]["response"]

    try:
        client = Groq(api_key=api_key)
        chat_completion = client.chat.completions.create(
            messages=[{"role": "user", "content": prompt}],
            model=model_name,
        )
        response_text = chat_completion.choices[0].message.content
        
        insert_plan = plpy.prepare(
            "INSERT INTO llm_cache (prompt_hash, model_name, response) VALUES ($1, $2, $3)", 
            ["text", "text", "text"]
        )
        plpy.execute(insert_plan,[prompt_hash, model_name, response_text])
        
        plpy.notice("Groq API: Запрос успешно выполнен и сохранен в кэш.")
        return response_text

    except Exception as e:
        plpy.error(f"Ошибка при обращении к Groq API: {e}")
$$;


-- Функция локальной генерации эмбеддингов для RAG (Мультиязычная версия)
CREATE OR REPLACE FUNCTION generate_embedding(text_to_embed TEXT)
RETURNS vector(384) 
LANGUAGE plpython3u
AS $$
    import plpy
    
    # GD (Global Dictionary) кэширует модель в памяти между вызовами
    if "embed_model" not in GD:
        try:
            from sentence_transformers import SentenceTransformer
            model_name = 'paraphrase-multilingual-MiniLM-L12-v2'
            
            plpy.notice(f"Загрузка ML модели: {model_name} ...")
            GD["embed_model"] = SentenceTransformer(model_name)
            plpy.notice("ML Модель успешно загружена в RAM сервера СУБД.")
        except ImportError:
            plpy.error("Библиотека sentence-transformers не найдена. Проверьте Dockerfile.")
        except Exception as e:
            plpy.error(f"Ошибка при загрузке модели: {e}")
            
    # Забираем модель из памяти и векторизуем
    model = GD["embed_model"]
    
    # encode возвращает numpy array, конвертируем в обычный Python list
    embedding = model.encode(text_to_embed)
    return embedding.tolist()
$$;


-- Таблица для хранения векторизованных отзывов Olist
CREATE TABLE IF NOT EXISTS review_embeddings (
    review_id VARCHAR(32) PRIMARY KEY,
    review_score SMALLINT,
    review_text TEXT,
    embedding vector(384)
);

-- Индекс для ускорения поиска
CREATE INDEX IF NOT EXISTS idx_review_embeddings_embedding 
ON review_embeddings USING hnsw (embedding vector_cosine_ops);

-- Функция для наполнения таблицы векторами (базовый инструмент инженера данных)
CREATE OR REPLACE PROCEDURE vectorize_reviews(batch_size INTEGER DEFAULT 50)
LANGUAGE plpgsql
AS $$
DECLARE
    row_record RECORD;
    v_embedding vector(384);
    counter INT := 0;
BEGIN
    -- Берем отзывы из Olist (которые мы еще не векторизовали)
 FOR row_record IN 
        SELECT r.review_id, r.review_score, r.review_comment_message 
        FROM olist_order_reviews r
        WHERE r.review_comment_message IS NOT NULL 
          AND length(r.review_comment_message) > 10
          AND NOT EXISTS (SELECT 1 FROM review_embeddings re WHERE re.review_id = r.review_id)
        LIMIT batch_size
    LOOP
        BEGIN
            v_embedding := generate_embedding(row_record.review_comment_message);
            INSERT INTO review_embeddings (review_id, review_score, review_text, embedding)
            VALUES (row_record.review_id, row_record.review_score, row_record.review_comment_message, v_embedding);
            counter := counter + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Ошибка при обработке отзыва %: %', row_record.review_id, SQLERRM;
            CONTINUE;
        END;
    END LOOP;
    
    IF counter > 0 THEN
        RAISE NOTICE 'Успешно векторизовано отзывов в этой пачке: %', counter;
    ELSE
        RAISE NOTICE 'Все доступные отзывы уже векторизованы или выборка пуста.';
    END IF;
END;
$$;


-- ФИНАЛЬНАЯ RAG ФУНКЦИЯ (Retrieval-Augmented Generation)
CREATE OR REPLACE FUNCTION ask_olist(user_question TEXT, knn_limit INTEGER DEFAULT 3)
RETURNS TEXT
LANGUAGE plpython3u
AS $$
    import plpy

    # 1. Векторизуем вопрос
    try:
        embed_plan = plpy.prepare("SELECT generate_embedding($1) AS q_vector", ["text"])
        q_vector_result = plpy.execute(embed_plan, [user_question])
        if not q_vector_result:
            return "Ошибка генерации вектора вопроса."
        question_vector = q_vector_result[0]["q_vector"]
    except Exception as e:
        return f"Ошибка при векторизации вопроса: {e}"

    # 2. Поиск похожих отзывов (ИСПРАВЛЕНО ЗДЕСЬ)
    search_sql = """
        SELECT review_text, review_score 
        FROM review_embeddings 
        ORDER BY embedding <=> $1::vector 
        LIMIT $2;
    """
    
    search_plan = plpy.prepare(search_sql, ["vector", "int4"])
    search_results = plpy.execute(search_plan, [question_vector, knn_limit])

    if not search_results:
         return "Я пока не нашел похожих отзывов в базе. Попробуйте запустить CALL vectorize_reviews(100); чтобы добавить данные."

    # 3. Формируем контекст
    context_text = ""
    for idx, row in enumerate(search_results):
        txt = row['review_text'].replace('\n', ' ')
        context_text += f"- Отзыв (оценка {row['review_score']}): {txt}\n"
         
    # 4. Формируем промпт для LLM
    prompt = f"""You are a helpful assistant for an e-commerce platform.
Use the following customer reviews to answer the user's question.
If the reviews do not contain the answer, say so politely.
ALWAYS answer in Russian.

Context from database:
{context_text}

User question: {user_question}

Answer:"""

    # 5. Вызов LLM
    try:
        chat_plan = plpy.prepare("SELECT groq_chat($1) AS llm_answer", ["text"])
        chat_result = plpy.execute(chat_plan, [prompt])
        return chat_result[0]["llm_answer"]
    except Exception as e:
        return f"Ошибка обращения к нейросети: {e}"
$$;
