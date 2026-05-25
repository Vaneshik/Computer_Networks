#!/usr/bin/env bash
# Генерация самоподписанных сертификатов для itmo.ru и itmo-team.ru
# Запускать один раз локально перед деплоем

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SCRIPT_DIR/key.pem" \
  -out "$SCRIPT_DIR/cert.pem" \
  -subj "/CN=itmo.ru/O=ITMO/C=RU" \
  -addext "subjectAltName=DNS:itmo.ru,DNS:www.itmo.ru,DNS:db.itmo-team.ru,DNS:auth.itmo-team.ru,DNS:itmo-team.ru"

echo "Сертификаты созданы: cert.pem, key.pem"
echo "  Срок: 365 дней"
echo "  SAN: itmo.ru, www.itmo.ru, db.itmo-team.ru, auth.itmo-team.ru"
