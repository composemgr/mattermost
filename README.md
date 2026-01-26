## 👋 Welcome to mattermost 🚀

Open-source team collaboration and messaging platform

## 📋 Description

Open-source team collaboration and messaging platform

## 🚀 Services

- **app**: mattermost/mattermost-team-edition:latest

### Infrastructure Components

- **db**: Mysql database


## 📦 Installation

### Option 1: Quick Install
```bash
curl -q -LSsf "https://raw.githubusercontent.com/composemgr/mattermost/main/docker-compose.yaml" -o compose.yml
```

### Option 2: Git Clone
```bash
git clone "https://github.com/composemgr/mattermost" ~/.local/srv/docker/mattermost
cd ~/.local/srv/docker/mattermost
docker compose up -d
```

### Option 3: Using composemgr
```bash
composemgr install mattermost
```

## 🔧 Configuration

### Environment Variables

```shell
TZ=America/New_York
APP_USER_NAME=administrator
APP_ADMIN_USER=admin
APP_ADMIN_PASS=changeme_admin_password
DB_USER_NAME=dbadmin
```

See `docker-compose.yaml` for complete list of configurable options.

## 🌐 Access

- **Web Interface**: http://172.17.0.1:59078

## 📂 Volumes

- `./rootfs/data/log/mattermost` - Data storage
- `./rootfs/data/mattermost` - Data storage
- `./rootfs/data/mattermost/plugins` - Data storage
- `./rootfs/config/mattermost` - Data storage
- `./rootfs/config/mattermost/plugins` - Data storage
- `./rootfs/data/db/mysql/mattermost` - Data storage

## 🔐 Security

- Change all default passwords before deploying to production
- Use strong secrets for all authentication tokens
- Configure HTTPS using a reverse proxy (nginx, traefik, caddy)
- Regularly update Docker images for security patches
- Backup your data regularly

## 🔍 Logging

```shell
docker compose logs -f app
```

## 🛠️ Management

```bash
# Start services
docker compose up -d

# Stop services
docker compose down

# Update to latest images
docker compose pull && docker compose up -d

# View logs
docker compose logs -f

# Restart services
docker compose restart
```

## 📋 Requirements

- Docker Engine 20.10+
- Docker Compose V2+

## 🤝 Author

🤖 casjay: [Github](https://github.com/casjay) 🤖  
🦄 composemgr: [Github](https://github.com/composemgr) 🦄
