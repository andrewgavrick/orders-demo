# Тестирование

## Команды

Контейнеры должны быть запущены. Из корня репозитория:

```sh
docker compose exec -e RAILS_ENV=test backend bundle exec rails db:prepare
docker compose exec backend bundle exec rspec
docker compose exec backend bundle exec rubocop
docker compose exec -e RAILS_ENV=test backend bundle exec rails zeitwerk:check
docker compose exec backend bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error
docker compose exec backend bundle exec bundler-audit check --update
docker compose exec frontend npm test
docker compose exec frontend npm run test:typecheck
docker compose exec frontend npm run lint
docker compose exec frontend npm run build
```

RSpec использует отдельную БД orders_ledger_test. Конфигурация не наследует
development DATABASE_URL. TEST_DATABASE_URL может менять host и credentials,
но конкурентные тесты требуют имя orders_ledger_test и pool не меньше трёх
соединений. Обновление базы уязвимостей bundler-audit требует доступа к сети.

## Backend

| Что проверяется | Файлы в backend/spec |
| --- | --- |
| Complete, Cancel, повторы, недостаток средств и откат | services/orders/ledger_operations_spec.rb |
| Конкурентные оплаты и возвраты | services/orders/ledger_concurrency_spec.rb |
| Баланс, валюты, соответствие платежа заказу, точное сторно и минус | services/ledger/post_spec.rb |
| Создание заказа вне HTTP и строгие типы JSON | services/orders/create_spec.rb, forms/orders/create_form_spec.rb |
| Неизменяемость финансовых полей проведённого заказа | models/posted_order_spec.rb |
| Типы, валидации, внешние ключи, CHECK и уникальность | models/order_domain_spec.rb, models/database_constraints_spec.rb |
| Сессия, права, HTTP-цикл, списки и ошибки | requests/ledger_api_spec.rb |
| Сиды: начальные средства, повтор, откат и запрет production | seeds/demo_spec.rb |
| Инъекция сбоя после реальных INSERT | infrastructure/financial_failure_spec.rb |
| Передача аргументов базовым сервисом без Rails | services/base_service_spec.rb |

Общие помощники запросов, журнала и конкурентности находятся в spec/support и
подключаются по metadata. spec_helper содержит настройки RSpec; rails_helper
поднимает Rails и тестовую БД только для тестов приложения. Проверки формы ввода
и BaseService можно запускать без Rails. В сервисных спеках используются
subject, let и контексты; связанные проверки атомарности остаются в одном сценарии.

Обычные примеры используют transactional fixtures. Финансовые проверки вызываются
через Ledger::Post: неверные проводки отклоняются до проведения, а внешняя
транзакция откатывает draft и записи. Отдельный тест проверяет отсутствие
пользовательских триггеров и ledger-функций в PostgreSQL.

Конкурентные тесты создают закоммиченные записи и работают через разные
соединения PostgreSQL. Координатор удерживает Account FOR UPDATE и проверяет
ожидание блокировок через pg_stat_activity. Ожидания ограничены таймаутами.
Очистка удаляет только записи своего примера в порядке внешних ключей.
Отключение триггеров и привилегии PostgreSQL superuser для очистки не нужны.

Rollback-тесты прерывают реальную запись второй Entry либо бросают исключение
после posting и изменения статуса. Затем сверяют заказ, оба баланса и журнал.

## Frontend

Vitest и React Testing Library проверяют выбор и восстановление сессии,
создание заказа с точной суммой, оплату и отмену, права продавца, раскрытие
проводок, ошибки API и защиту от устаревшего ответа загрузки. Отдельно проверяется
ошибка обновления журнала после успешной оплаты: сохранённый заказ остаётся виден.

Проверки работают в jsdom. Это не браузерные end-to-end тесты и не проверка
визуальной вёрстки. Типы тестового кода проверяются отдельным test:typecheck.

## Запуск на новой базе

Используйте отдельное имя базы с префиксом orders_boot_smoke, например:

```sh
docker compose exec -e DATABASE_URL=postgres://orders:orders@db:5432/orders_boot_smoke_review backend bundle exec rails db:prepare
docker compose exec -e DATABASE_URL=postgres://orders:orders@db:5432/orders_boot_smoke_review backend bundle exec rails runner --skip-executor script/verify_demo.rb
```

Для проверки именно свежей базы выберите ещё не использованное имя.
Скрипт проверяет повторные сиды и HTTP-цикл через Rails integration session:
выбор участника → создание → Complete дважды → Cancel дважды → журнал.
Проверяет балансы и отсутствие повторного платежа. Скрипт не использует браузер
или внешний HTTP-сервер и оставляет отменённый заказ в отдельной БД.

## CI

[Корневой workflow](../.github/workflows/ci.yml) запускается на push и pull request.
Backend job выполняет RSpec, RuboCop, Zeitwerk, Brakeman, bundler-audit и проверку
свежей базы. Дополнительно script/verify_upgrade.rb поднимает историческую схему
в отдельной пустой базе, создаёт проведённый платёж, применяет новые миграции,
сверяет неизменность финансовой истории и выполняет возврат после удаления триггеров.
Frontend job устанавливает зависимости, запускает тесты, проверку
типов, ESLint и сборку. Оба используют Docker Compose.
