# System Requirements Document (SRD): Payment Processing Service

## 1. Обзор системы и Бизнес цели
**Payment Processing Service** — микросервис для обработки входящих платежей пользователей, проведения проверок идемпотентности, обеспечения безопасности финансово критичных данных и взаимодействия с внешними платежными шлюзами (Payment Gateways)

### Основные задачи:
* Безопасный и идемпотентный прием платежей с защитой от двойных списаний
* Управление жизненным циклом транзакции
* Логирование всех изменений статусов для аудита

---

## 2. Архитектура безопасности и авторизация (Security & Auth)

1. **Аутентификация и проброс контекста**
   * Внешние запросы от клиентов проходят аутентификацию на **API Gateway** по **JWT** токену
   * API Gateway проверяет токен и транслирует верифицированный заголовок `X-User-ID` во внутренний Payment Service
   * Payment Service сверяет `user_id` из JSON-тела с заголовком `X-User-ID` для защиты от BOLA атак

2. **Защита целостности данных (Tamper Protection):**
   * Запрос на проведение платежа содержит заголовок `X-Signature` (HMAC-SHA256 подпись JSON-тела). Это исключает возможность подмены параметров (`amount`, `currency`) при передаче.

3. **Идемпотентность и Rate Limiting:**
   * Каждая транзакция требует передачи уникального `X-Idempotency-Key` (UUIDv4). Ключи кэшируются в Redis на время жизни транзакции во внешнем эквайринге
   * Защита от спама и брутфорса реализуется через Rate Limiting на уровне API Gateway

---

### Edge Cases

1. **Parallel Requests Handling (Race Condition):**
   * Для предотвращения параллельной двойной инициализации при одновременных запросах используется **Distributed Lock в Redis (`SETNX`)** по `X-Idempotency-Key`
   * На уровне базы данных установлено ограничение `UNIQUE (idempotency_key)`

2. **Expired Cache**
   * При отсутствия ключа в Redis происходит fallback запрос в PostgreSQL.
   * Если транзакция находится в статусе `PENDING/PROCESSING` более 15 (время жизни сессии эквайринга) минут, сервис автоматически переводит ее в `CANCELLED` по таймауту и запрашивает у клиента инициализацию нового платежа

---

## 2. Функциональные и Нефункциональные требования (FR / NFR)

### Функциональные требования:
* **FR-1:** Система должна предоставлять REST API для инициализации платежа
* **FR-2:** Система обязана проверять заголовок `X-Idempotency-Key`. Повторный запрос с тем же ключом должен возвращать существующий статус платежа без повторного списания
* **FR-3:** Система должна фиксировать историю смены статусов в `payment_status_logs`

### Нефункциональные требования:
* **NFR-1** Время отклика API создания платежа $p95 < 200ms$ (без учета задержки внешнего шлюза)
* **NFR-2** Гарантия обработки платежей по принципу *At-Least-Once* с использованием идемпотентности
* **NFR-3** Хранение сумм в точном типе `NUMERIC(12,2)` для исключения ошибок округления

---

## 3. Sequence-диаграмма взаимодействия (PlantUML / Mermaid)

```mermaid
sequenceDiagram
    autonumber
    actor Client as Клиент (Frontend/App)
    participant API as Payment Service (Backend)
    participant DB as PostgreSQL
    participant Gateway as Внешний Платежный Шлюз

    Client->>API: POST /api/v1/payments (Header: X-Idempotency-Key)
    API->>DB: Проверка Idempotency Key в БД
    alt Ключ уже существует
        DB-->>API: Возврат существующего payment_id и статуса
        API-->>Client: 200 OK / 409 Conflict (данные платежа)
    else Новый платеж
        API->>DB: INSERT INTO payments (status = 'PENDING')
        API->>Gateway: POST /v1/charge (Инициализация во внешнем шлюзе)
        alt Шлюз ответил успешно
            Gateway-->>API: 200 OK (external_provider_id, redirect_url)
            API->>DB: UPDATE payments SET status = 'PROCESSING'
            API-->>Client: 201 Created (redirect_url)
        else Ошибка шлюза / Таймаут
            Gateway-->>API: 5xx Error / Timeout
            API->>DB: UPDATE payments SET status = 'FAILED'
            API-->>Client: 502 Bad Gateway (Ошибка платежного шлюза)
        end
    end