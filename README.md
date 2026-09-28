# Orders Demo

Приложение для заказов и расчётов между покупателем и продавцом.
Rails API, React и PostgreSQL в одном репозитории. Деньги учитываются двойной
записью: оплата и возврат создают неизменяемые проводки, баланс рассчитывается
из журнала. Отрицательный баланс кошелька запрещён.

Финансовые сценарии выполняются Ruby-сервисами в транзакциях с блокировками.
В текущей схеме нет пользовательских SQL-функций и триггеров. Представления API
используют Jbuilder, пагинация — Kaminari.

## Запуск

Нужны Docker с Linux containers и Docker Compose. На Windows запустите Docker
Desktop. Ruby, Node.js, PostgreSQL и Make на компьютере устанавливать не нужно.
Все команды выполняются из корня репозитория, в том числе в PowerShell.

```sh
docker compose up -d --build
docker compose logs -f backend frontend
```

Дождитесь запуска Rails и Vite. Ctrl+C закрывает просмотр логов, контейнеры
продолжают работать. Первый запуск устанавливает зависимости и готовит БД.

Откройте [localhost:5173](http://localhost:5173). Проверка Rails:
[localhost:3000/up](http://localhost:3000/up).

На новой БД автоматически создаются семь участников с **1 000 000 USD** каждому.
Для существующей БД демоданные можно добавить вручную:

```sh
docker compose exec backend bundle exec rails db:seed
```

Повторные сиды не начисляют деньги заново и не восстанавливают потраченный баланс.
Заказов в сидах нет.

## Что попробовать

1. Выберите участника, создайте заказ с продавцом и суммой.
2. Нажмите Complete: деньги перейдут от покупателя продавцу.
3. Раскройте проводки операции в журнале.
4. Нажмите Cancel: появится отдельная операция возврата.
5. Через Switch participant выберите продавца и проверьте баланс и продажи.
   Refresh загружает изменения, сделанные в другой вкладке.

Выбор участника — **деморежим без проверки личности**, а не полноценная
аутентификация. Читать заказ могут оба участника, проводить и отменять — только
покупатель. Если продавец потратил выручку и денег на возврат не хватает,
отмена отклоняется.

## Проверки

```sh
docker compose exec -e RAILS_ENV=test backend bundle exec rails db:prepare
docker compose exec backend bundle exec rspec
docker compose exec backend bundle exec rubocop
docker compose exec frontend npm test
docker compose exec frontend npm run test:typecheck
docker compose exec frontend npm run lint
docker compose exec frontend npm run build
```

Полный набор проверок, включая конкурентность, безопасность и запуск на новой
БД, описан в [testing.md](docs/testing.md) и выполняется в GitHub Actions.

## Структура и документация

```text
backend/    Rails API, миграции и RSpec
frontend/   React + TypeScript, Vite и Vitest
dev/        Dockerfile для Rails
docs/       Архитектура, финансовая модель, API и разработка
.github/    GitHub Actions
```

| Документ | Содержание |
| --- | --- |
| [Архитектура](docs/architecture.md) | Модели, слои приложения и границы демо |
| [Финансовая модель](docs/ledger.md) | Оплата, сторно, блокировки и ограничения БД |
| [API](docs/api.md) | Маршруты, права, форматы запросов и ошибки |
| [Разработка](docs/development.md) | Окружение, команды и проблемы запуска |
| [Тестирование](docs/testing.md) | Сценарии, конкурентность и CI |

Стек: Ruby 3.4.10, Rails 8.1, PostgreSQL 17; Node.js 24, React 19,
TypeScript и Vite 8. Точные версии зависимостей закреплены в lock-файлах.

Остановка: `docker compose down`. Данные остаются в Docker volume.
