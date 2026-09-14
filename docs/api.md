# Ledger API

Все бизнес-маршруты имеют префикс `/v1`. Frontend использует cookie-сессию.

## Session и доступ

`POST /v1/session` с `{ "actor_id": 2 }` выбирает существующий Actor вида `user`
и возвращает `{ "actor": { "id": 2, "name": "…", "kind": "user" } }` с кодом 201.
Actor id передаётся JSON-числом. Ответ устанавливает HttpOnly session cookie
с SameSite=Strict; в production cookie также Secure.

Это **демовыбор участника, а не аутентификация**: паролей и проверки личности
нет, любой пользователь демо может выбрать любого actor из списка.

- `GET /v1/actors` — доступный без session список участников `user`; системные
  actor и балансы не включаются. Сортировка `name ASC, id ASC`.
- `GET /v1/session` — текущий actor, либо JSON 401.
- `DELETE /v1/session` — сброс session, 204.
- Остальные методы требуют session. Тело POST/DELETE — JSON с
  `Content-Type: application/json`. GET-параметры передаются в query string.
- Профиль со счетами и журнал доступны только выбранному actor.
- Заказ видят его покупатель и продавец; Complete/Cancel доступны покупателю.
  Посторонний actor получает 404 на заказ, продавец — 403 при попытке мутации.

## Профиль и счета

`GET /v1/actors/:id`:

```json
{
  "actor": { "id": 2, "name": "Buyer", "kind": "user" },
  "accounts": [
    { "id": 7, "actor_id": 2, "account_type": "liability", "purpose": "wallet", "currency": "USD", "balance_minor": 1000 }
  ]
}
```

Баланс вычисляется из проведённых проводок и сериализуется целым JSON-числом.
У actor может быть несколько счетов, поэтому ответ содержит массив `accounts`.

## Заказы

`POST /v1/actors/:actor_id/orders`:

```json
{ "order": { "seller_id": 3, "amount_minor": 250, "currency": "USD" } }
```

Ответ 201: `{ "order": { ... } }`. Покупатель определяется session и должен
совпадать с actor в URL. `buyer_id`, `status` и прочие финансовые атрибуты
из тела не принимаются. Продавец должен быть существующим `user`, отличным
от покупателя. У обоих нужны кошельки в указанной валюте.

`amount_minor` — положительное целое JSON-число в диапазоне PostgreSQL bigint;
строки, дроби и ноль не принимаются. Валюта — три заглавные буквы.
Создание не списывает деньги и не создаёт проводки.

`GET /v1/actors/:actor_id/orders` возвращает `{ "orders": [...], "meta": {...} }`.
Список включает покупки и продажи выбранного actor, сортировка:
`created_at DESC, id DESC`. `GET /v1/orders/:id` возвращает `{ "order": {...} }`.

Поля заказа: `id`, `buyer_id`, `seller_id`, `amount_minor`, `currency`,
`status`, `created_at`, `updated_at`.

`POST /v1/orders/:id/complete` и `POST /v1/orders/:id/cancel` принимают `{}`.
Успех: 200, `{ "order": {...}, "accounts": [...] }`. Здесь accounts содержит
только счета текущего actor, затронутые сервисом; чужие балансы не раскрываются.
Повторные вызовы идемпотентны. Недостаток средств при списании или возврате — 422.

## Финансовый журнал

`GET /v1/actors/:actor_id/transactions` возвращает проведённые операции,
затрагивающие счета actor, без дубликатов, с сортировкой `created_at DESC, id DESC`.
Участник видит все проводки операции, включая встречные, но не баланс контрагента.

Виды операций: `charge`, `reversal`, `opening_balance`. У `opening_balance`
поля `order_id` и `reversal_of_id` равны null. Это начальное финансирование
кошелька из seeds; отдельного публичного endpoint для пополнения нет.

```json
{
  "transactions": [{
    "id": 101,
    "order_id": 42,
    "kind": "reversal",
    "reversal_of_id": 100,
    "created_at": "2026-09-12T10:00:00.000Z",
    "posted_at": "2026-09-12T10:00:00.000Z",
    "entries": [
      { "id": 201, "account_id": 7, "actor_id": 2, "direction": "credit", "amount_minor": 250, "currency": "USD", "created_at": "2026-09-12T10:00:00.000Z" },
      { "id": 202, "account_id": 8, "actor_id": 3, "direction": "debit", "amount_minor": 250, "currency": "USD", "created_at": "2026-09-12T10:00:00.000Z" }
    ]
  }],
  "meta": { "page": 1, "per_page": 50, "total": 1 }
}
```

Во всех списках доступны `page` (1..999999) и `per_page` (1..100, default 50).
Несуществующая страница возвращает пустой массив; неверные параметры — 400.

## Ошибки

```json
{ "error": { "code": "insufficient_funds", "message": "Insufficient funds in buyer wallet" } }
```

| HTTP | Коды |
| --- | --- |
| 400 | `bad_request`: неправильная форма запроса или пагинация |
| 401 | `unauthorized`: actor не выбран |
| 403 | `forbidden`: действие недоступно текущему actor |
| 404 | `not_found`: запись отсутствует или заказ недоступен |
| 415 | `unsupported_media_type`: мутация отправлена не как JSON |
| 422 | `validation_error`, `invalid_order`, `account_not_found`, `invalid_transition`, `insufficient_funds` |

Ошибки ActiveRecord-валидации дополнительно содержат `error.details`.
Неожиданные исключения сервисов и повреждение ledger не превращаются в 422.
