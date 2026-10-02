```mermaid
stateDiagram-v2
	[*] --> PENDING: Создание платежа
	PENDING --> PROCESSING: Переход на эквайринг / Получение redirect_url
	PROCESSING --> SUCCESS: Успешный Webhook от шлюза
	PROCESSING --> FAILED: Ошибка (Нехватка средств / Отклонено)
	PROCESSING --> CANCELLED: Таймаут сессии

		SUCCESS --> REFUNDED: Refund API

		SUCCESS --> [*]
		FAILED --> [*]
		CANCELLED --> [*]
		REFUNDED --> [*]
```
