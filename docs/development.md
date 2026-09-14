# Локальная разработка

## Окружение

Запуск описан в [README](../README.md#запуск). Все команды ниже выполняются
из корня репозитория. Docker Desktop должен работать в режиме Linux containers.

| Сервис | Адрес / назначение |
| --- | --- |
| frontend | localhost:5173, Vite с proxy в Rails |
| backend | localhost:3000, Rails API |
| db | PostgreSQL 17, внутри Compose как db:5432 |

Исходники подключены в контейнеры. Gems, node_modules и PostgreSQL хранятся
в отдельных Docker volumes. Порты приложений опубликованы только на localhost.
Учётные данные PostgreSQL из Compose предназначены для локального окружения.

Rails при старте выполняет db:prepare: готовит БД и применяет миграции.
Новая база загружается из structure.sql и заполняется сидами. Demo::Seeds
создаёт семь пользователей с USD-кошельками; начальная сумма задаётся
OPENING_AMOUNT в backend/app/services/demo/seeds.rb.
Повторные сиды не дублируют начальные операции. В production они запрещены.

## Команды

```sh
docker compose logs -f
docker compose exec backend bundle exec rails console
docker compose exec backend bundle exec rails db:migrate
docker compose exec backend bundle exec rails db:seed
docker compose down
```

down сохраняет данные. **docker compose down -v удаляет тома, включая всю БД.**

После изменения зависимостей обновите lock-файлы:

```sh
docker compose run --rm --no-deps backend bundle install
docker compose run --rm --no-deps frontend npm install
```

Makefile — необязательные сокращения для build, up, down, logs, shell и console.
На Windows без Make используйте команды Docker Compose.

## Если запуск не удался

| Симптом | Что проверить |
| --- | --- |
| Ошибка dockerDesktopLinuxEngine / daemon unavailable | Запущен ли Docker Desktop, включены ли Linux containers |
| make не найден | Используйте docker compose напрямую |
| Frontend завершился на npm | Прочитайте начало ошибки через docker compose logs frontend; проверьте package.json и package-lock.json |
| Порт 3000 или 5173 занят | Освободите порт либо измените host-port в compose.yml |
| Backend ещё недоступен | Первый запуск устанавливает gems; проверьте docker compose logs backend |

Не удаляйте тома для исправления ошибок зависимостей: это удалит и данные БД.

## Git

Один репозиторий для backend, frontend, окружения и документации.
Коммиты группируются по изменению, а не обязательно по каталогу:
feat(api), feat(web), chore(dev), docs.

В Git не входят локальные ключи Rails, .env, логи, зависимости и результаты
сборки. Зашифрованный credentials.yml.enc хранится в репозитории;
master.key остаётся локальным. Development/test не требуют передачи этого ключа.
