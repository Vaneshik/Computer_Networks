# Пояснительная записка

## Что реализовано

Вся сеть поднимается через ContainerLab одной командой и эмулирует корпоративную инфраструктуру на 17 Docker-контейнерах.

Трафик идёт так: клиент → ISP-роутер → два edge-узла (BGP anycast, AS65001/AS65002) → L3/L4-балансировщик (nginx stream) → файрвол (nftables) → L7-балансировщик (nginx HTTPS) → три веб-бэкенда.

Что из ТЗ закрыто:

- **Anycast** — два edge-узла анонсируют один VIP (10.99.0.1/32 и fd00:99::1/128) через eBGP, ISP устанавливает ECMP-маршрут на оба. Географически это были бы разные PoP, здесь это два контейнера на одной машине.
- **L3/L4 LB** — nginx stream module, VIP на интерфейсе, проксирует TCP-поток без разбора содержимого.
- **L7 LB** — nginx, терминирует TLS, раскладывает запросы по трём бэкендам round-robin, различает домены по Host-заголовку.
- **Файрвол** — nftables, stateful, блокирует прямой доступ к PostgreSQL из DMZ, пропускает только 443 на lb-l7.
- **NAT** — nftables masquerade на nat-gw, внутренняя сеть ходит в интернет через clab management network.
- **DNS** — два экземпляра CoreDNS: itmo.ru (публичная зона, 1.1.1.53) и itmo-team.ru (внутренняя зона, 10.3.0.53).
- **SSO** — Keycloak (realm itmo) + oauth2-proxy перед DbGate. Неавторизованный запрос к db.itmo-team.ru редиректится на Keycloak.
- **SSH SSO** — Teleport, certificate-based SSH, web-интерфейс на порту 3080.
- **IPv6** — dual-stack на публичном пути: client → ISP → edges → lb-l34 → firewall → lb-l7 → web1/2/3. Внутренние сервисы (Keycloak, Teleport, postgres) только IPv4.

Что не до конца: IPv6 не покрывает внутренние сервисы, Teleport требует ручной регистрации первого пользователя через браузер.

---

## Как запустить

Тестировалось на **Windows 11 + WSL2 (Ubuntu 22.04) + Docker Desktop**. На macOS должно работать аналогично, только `prepare-bridges.sh` нужно запускать без `wsl --shutdown`-специфики.

### Зависимости

- Docker (Desktop или Engine)
- [ContainerLab](https://containerlab.dev/install/):
  ```bash
  bash -c "$(curl -sL https://get.containerlab.dev)"
  ```

### Запуск

```bash
# Лучше работать из Linux FS, не /mnt/c/...
cp -r /mnt/c/.../task_03 ~/task_03 && cd ~/task_03   # только для Windows

# Один раз: сертификаты и локальные образы
bash configs/certs/gen-certs.sh
bash scripts/build-images.sh

# Создать Linux bridge-интерфейсы (нужно после каждого wsl --shutdown на Windows)
bash scripts/prepare-bridges.sh

# Поднять топологию
sudo clab deploy -t topology.clab.yml

# Подождать ~2 минуты, потом прогнать тесты
sleep 120 && bash test-all.sh
```

### Открыть в браузере

Добавить в `/etc/hosts` (на Windows — `C:\Windows\System32\drivers\etc\hosts`, от администратора):

```
127.0.0.1   itmo.ru www.itmo.ru db.itmo-team.ru auth.itmo-team.ru
```

| Адрес | Что |
|---|---|
| https://itmo.ru | публичный сайт, 3 бэкенда |
| https://db.itmo-team.ru | DbGate через SSO (admin/admin123) |
| https://auth.itmo-team.ru | Keycloak admin (admin/admin123) |
| http://10.3.0.60:3080 | Teleport web UI |

Сертификаты самоподписанные — браузер попросит добавить исключение.

### Teleport SSH

```bash
# Получить invite-ссылку
docker exec clab-itmo-net-teleport cat /var/lib/teleport/admin-invite.txt

# Открыть в браузере, задать пароль
# Потом из client-контейнера:
docker exec -it clab-itmo-net-client sh
# установить tsh и:
tsh login --proxy=10.3.0.60:3080 --insecure --user=admin
tsh ssh root@teleport.itmo-team.ru
```

### Остановить

```bash
sudo clab destroy -t topology.clab.yml
```

---

## Почему такой стек

| Что | Чем | Почему |
|---|---|---|
| Anycast | FRR (eBGP) | стандартный стек, работает в контейнерах |
| L3/L4 LB | nginx stream | не требует IPVS/keepalived, работает везде |
| L7 LB | nginx | TLS termination + Host routing в одном месте |
| Файрвол | nftables | современная альтернатива iptables |
| SSO | Keycloak + oauth2-proxy | проверенная связка для OIDC |
| SSH SSO | Teleport | единственный разумный open-source вариант |
| DNS | CoreDNS | простой конфиг, зонные файлы |
| DB UI | DbGate | лёгкий, postgres из коробки |
| Топология | ContainerLab | специально для сетевых лабораторий |

Изначально планировался деплой на два VM в Yandex Cloud с GRE-туннелем между edge и internal, но в итоге всё запускается на одной машине — anycast эмулируется между контейнерами, поведение L3 идентично.
