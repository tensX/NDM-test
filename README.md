# nginx XFF chain test

4 nginx в reverse proxy перед приложением. Цепочки произвольной длины, защита X-Forwarded-For от подделки клиентом.

## Идея

На каждом nginx - список IP всех остальных наших nginx. Если запрос пришел с IP из этого списка, это свой прокси и XFF добавляется в цепочку. Если с любого другого IP - это клиент, XFF переписывается с нуля и в нем остается только реальный IP клиента.

Работает потому что `$remote_addr` в nginx - IP реально установленного TCP-соединения, на уровне curl/HTTP его не подделать. А X-Forwarded-For - просто строка в HTTP-запросе.

Реализация - блоки `geo` (свой/чужой) + `map` (что класть в исходящий XFF). Конфиг один и тот же на всех 4 nginx, см. `nginx/nginx.conf`.

## Стенд

- 4 nginx с фиксированными IP в `172.28.0.0/16`: `.11`-`.14`. Наружу: 8081-8084.
- `traefik/whoami` на `.20`, наружу не торчит, отдает дамп заголовков.
- `/app` - прямо в приложение. `/via/nginxN/...` - на соседний nginx с пробросом хвоста пути.

`curl localhost:8081/via/nginx2/via/nginx3/app` → `user -> nginx1 -> nginx2 -> nginx3 -> app`.

При тестировании с хоста source IP в nginx всегда `172.28.0.1` (docker bridge gateway, NAT). В реале без NAT в `$remote_addr` будет реальный IP юзера.

## Запуск

```
docker compose up -d
```

Стоп: `docker compose down`.

## Тесты

`bash test.sh` или команды ниже по одной.

### 1. Один nginx, любая точка входа

```
curl -s http://localhost:8081/app | grep -i x-forwarded-for
curl -s http://localhost:8082/app | grep -i x-forwarded-for
curl -s http://localhost:8083/app | grep -i x-forwarded-for
curl -s http://localhost:8084/app | grep -i x-forwarded-for
```

Везде `X-Forwarded-For: 172.28.0.1`.

### 2. Цепочки

```
curl -s http://localhost:8081/via/nginx2/app
curl -s http://localhost:8081/via/nginx2/via/nginx3/app
curl -s http://localhost:8081/via/nginx2/via/nginx3/via/nginx4/app
```

В XFF:
- `172.28.0.1, 172.28.0.11`
- `172.28.0.1, 172.28.0.11, 172.28.0.12`
- `172.28.0.1, 172.28.0.11, 172.28.0.12, 172.28.0.13`

### 3. Произвольный порядок и точка входа

```
curl -s http://localhost:8084/via/nginx1/via/nginx2/app
# XFF: 172.28.0.1, 172.28.0.14, 172.28.0.11

curl -s http://localhost:8082/via/nginx4/via/nginx3/app
# XFF: 172.28.0.1, 172.28.0.12, 172.28.0.14
```

### 4. Подделка XFF

```
curl -s -H 'X-Forwarded-For: 1.2.3.4, 6.6.6.6' http://localhost:8081/app
# XFF: 172.28.0.1 - подделанное выкинуто

curl -s -H 'X-Forwarded-For: 6.6.6.6' http://localhost:8081/via/nginx2/via/nginx3/app
# XFF: 172.28.0.1, 172.28.0.11, 172.28.0.12

curl -s -H 'X-Forwarded-For: 6.6.6.6' http://localhost:8083/via/nginx4/app
# XFF: 172.28.0.1, 172.28.0.13
```

6.6.6.6 нигде не появляется - защита работает независимо от точки входа.
