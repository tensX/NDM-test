#!/usr/bin/env bash
# curl-тесты к стенду. запускать после `docker compose up -d`.

xff() {
    curl -s "$@" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-forwarded-for"{print $2}'
}

echo "[direct hop]"
for p in 8081 8082 8083 8084; do
    echo " :$p/app -> $(xff http://localhost:$p/app)"
done

echo
echo "[chains]"
echo " 1->2:       $(xff http://localhost:8081/via/nginx2/app)"
echo " 1->2->3:    $(xff http://localhost:8081/via/nginx2/via/nginx3/app)"
echo " 1->2->3->4: $(xff http://localhost:8081/via/nginx2/via/nginx3/via/nginx4/app)"
echo " 4->1->2:    $(xff http://localhost:8084/via/nginx1/via/nginx2/app)"
echo " 2->4->3:    $(xff http://localhost:8082/via/nginx4/via/nginx3/app)"

echo
echo "[spoof, X-Forwarded-For: 6.6.6.6]"
H='X-Forwarded-For: 6.6.6.6'
echo " :8081/app                            $(xff -H "$H" http://localhost:8081/app)"
echo " :8081/via/nginx2/via/nginx3/app      $(xff -H "$H" http://localhost:8081/via/nginx2/via/nginx3/app)"
echo " :8083/via/nginx4/app                 $(xff -H "$H" http://localhost:8083/via/nginx4/app)"
echo " :8084/via/nginx1/via/nginx2/app      $(xff -H "$H" http://localhost:8084/via/nginx1/via/nginx2/app)"
echo
echo "6.6.6.6 не должен появиться нигде выше."
