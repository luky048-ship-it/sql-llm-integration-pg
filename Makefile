EXTENSION = pg_llm_utils
DATA = pg_llm_utils--1.0.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
