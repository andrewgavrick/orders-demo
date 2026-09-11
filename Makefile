.PHONY: build up down logs shell console

build:
	docker compose build

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f

shell:
	docker compose exec backend bash

console:
	docker compose exec backend bundle exec rails console
