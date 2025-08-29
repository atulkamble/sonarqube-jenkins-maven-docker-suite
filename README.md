Awesome—here’s a complete, ready-to-run mini-stack with **SonarQube + PostgreSQL + Jenkins + Maven** via Docker Compose, including an **Amazon Linux one-shot install script**, repo name, project tree, and a **README.md** you can drop straight into GitHub.

---

# Repo name

`sonarqube-jenkins-maven-docker-suite`

---

# Project tree

```
sonarqube-jenkins-maven-docker-suite/
├─ docker-compose.yml
├─ .env.example
├─ jenkins/
│  ├─ Dockerfile
│  └─ plugins.txt
├─ scripts/
│  ├─ install_amazon_linux.sh
│  ├─ init_sonar_admin_and_token.sh
│  └─ jenkins_admin_password.sh
├─ sample-app/
│  ├─ pom.xml
│  └─ Jenkinsfile
└─ README.md
```

---

# 1) `docker-compose.yml`

```yaml
version: "3.8"

networks:
  devops-net:
    driver: bridge

volumes:
  pg_data:
  sonarqube_data:
  sonarqube_extensions:
  jenkins_home:
  maven_repo:

services:
  postgres:
    image: postgres:15
    container_name: pg-sonar
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-sonar}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-sonarpass}
      POSTGRES_DB: ${POSTGRES_DB:-sonarqube}
    volumes:
      - pg_data:/var/lib/postgresql/data
    networks:
      - devops-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 10s
      timeout: 5s
      retries: 10

  sonarqube:
    image: sonarqube:community
    container_name: sonarqube
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://postgres:5432/${POSTGRES_DB:-sonarqube}
      SONAR_JDBC_USERNAME: ${POSTGRES_USER:-sonar}
      SONAR_JDBC_PASSWORD: ${POSTGRES_PASSWORD:-sonarpass}
      # Tune if you have >2GB RAM free for SonarQube
      SONAR_ES_BOOTSTRAP_CHECKS_DISABLE: "true"
    ports:
      - "9000:9000"
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_extensions:/opt/sonarqube/extensions
    networks:
      - devops-net

  jenkins:
    build:
      context: ./jenkins
      dockerfile: Dockerfile
    container_name: jenkins
    restart: unless-stopped
    user: root
    environment:
      JAVA_OPTS: "-Djenkins.install.runSetupWizard=false"
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - maven_repo:/var/maven/repo
    networks:
      - devops-net
    depends_on:
      - sonarqube

  # Optional helper container to run Maven locally if you want (outside Jenkins)
  maven:
    image: maven:3.9-eclipse-temurin-17
    container_name: maven-cli
    working_dir: /workspace
    entrypoint: ["bash", "-lc"]
    command: ["mvn --version && bash"]
    volumes:
      - ./sample-app:/workspace
      - maven_repo:/root/.m2/repository
    networks:
      - devops-net
```

---

# 2) `.env.example`

```bash
# Copy to .env and adjust if needed
POSTGRES_USER=sonar
POSTGRES_PASSWORD=sonarpass
POSTGRES_DB=sonarqube

# For Sonar admin bootstrap script
SONARQUBE_HOST=http://localhost:9000
SONARQUBE_ADMIN_NEW_PASSWORD=ChangeMe123!
SONARQUBE_TOKEN_NAME=jenkins-token
```

---

# 3) Jenkins image + plugins

## `jenkins/Dockerfile`

```Dockerfile
FROM jenkins/jenkins:lts-jdk17

# Pre-install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Preconfigure Maven Global Settings directory
USER root
RUN mkdir -p /var/maven/repo && chown -R jenkins:jenkins /var/maven/repo
USER jenkins
```

## `jenkins/plugins.txt`

```
git
workflow-aggregator
pipeline-utility-steps
blueocean
credentials
credentials-binding
docker-workflow
configuration-as-code
sonar
job-dsl
pipeline-stage-view
```

---

# 4) Amazon Linux full installation script

## `scripts/install_amazon_linux.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Tested on Amazon Linux 2023
echo "[INFO] Updating OS packages..."
sudo dnf -y update

echo "[INFO] Installing prerequisites..."
sudo dnf -y install git curl jq util-linux-user

echo "[INFO] Installing Docker..."
# Amazon Linux 2023
sudo dnf -y install docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER || true

echo "[INFO] Installing Docker Compose plugin..."
# docker-compose v2 (compose CLI plugin)
DOCKER_COMPOSE_VERSION="v2.29.7"
sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose version

echo "[INFO] Setting vm.max_map_count for SonarQube (requires sudo)..."
if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Optional: raise file descriptors a bit
if ! grep -q "fs.file-max" /etc/sysctl.conf; then
  echo "fs.file-max=131072" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

REPO_DIR="${1:-sonarqube-jenkins-maven-docker-suite}"

if [ ! -d "$REPO_DIR" ]; then
  echo "[INFO] Cloning example repo skeleton..."
  git clone https://github.com/example/${REPO_DIR}.git || true
fi

cd "$REPO_DIR" || { echo "Repo dir not found"; exit 1; }

echo "[INFO] Creating .env from template if missing..."
[ -f .env ] || cp .env.example .env

echo "[INFO] Bringing stack up..."
docker-compose up -d

echo
echo "[SUCCESS] Stack is starting."
echo "Jenkins:    http://<EC2-Public-IP>:8080"
echo "SonarQube:  http://<EC2-Public-IP>:9000"
echo
echo "NOTE: Log out and back in (or 'newgrp docker') to use Docker without sudo."
```

> 💡 Run on your EC2 (Amazon Linux 2023, t3.large recommended):

```bash
curl -fsSL https://raw.githubusercontent.com/<your-gh-user>/sonarqube-jenkins-maven-docker-suite/main/scripts/install_amazon_linux.sh -o install.sh
bash install.sh
```

---

# 5) SonarQube admin bootstrap & token generator (optional)

**Use this once SonarQube is up** to:
(1) change default admin password `admin → $SONARQUBE_ADMIN_NEW_PASSWORD` and
(2) create a token named `$SONARQUBE_TOKEN_NAME`.

## `scripts/init_sonar_admin_and_token.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SONARQUBE_HOST="${SONARQUBE_HOST:-http://localhost:9000}"
SONARQUBE_ADMIN_NEW_PASSWORD="${SONARQUBE_ADMIN_NEW_PASSWORD:-ChangeMe123!}"
SONARQUBE_TOKEN_NAME="${SONARQUBE_TOKEN_NAME:-jenkins-token}"

echo "[INFO] Waiting for SonarQube to be ready..."
for i in {1..60}; do
  if curl -sSf "$SONARQUBE_HOST/api/system/health" | jq -e '.health=="GREEN"' >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

echo "[INFO] Changing default admin password..."
curl -sSf -u admin:admin -X POST "$SONARQUBE_HOST/api/users/change_password" \
  -d "login=admin&previousPassword=admin&password=${SONARQUBE_ADMIN_NEW_PASSWORD}"

echo "[INFO] Generating token..."
TOKEN_JSON=$(curl -sSf -u admin:${SONARQUBE_ADMIN_NEW_PASSWORD} \
  -X POST "$SONARQUBE_HOST/api/user_tokens/generate" -d "name=${SONARQUBE_TOKEN_NAME}")
TOKEN=$(echo "$TOKEN_JSON" | jq -r '.token')

echo "[SUCCESS] SONAR_TOKEN=${TOKEN}"
```

---

# 6) Quick helper to get Jenkins initial admin password

## `scripts/jenkins_admin_password.sh`

```bash
#!/usr/bin/env bash
docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword || true
```

---

# 7) Sample Maven app + Jenkins pipeline (with Sonar)

## `sample-app/pom.xml`

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                             https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>io.cloudnautic.demo</groupId>
  <artifactId>hello-sonar-jenkins</artifactId>
  <version>1.0.0</version>
  <name>Hello Sonar Jenkins</name>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
  <dependencies>
    <!-- add any dependencies you like -->
  </dependencies>
</project>
```

## `sample-app/Jenkinsfile`

```groovy
pipeline {
  agent { docker { image 'maven:3.9-eclipse-temurin-17' args '-v /var/maven/repo:/root/.m2/repository' } }

  environment {
    SONAR_HOST_URL = credentials('sonar-host-url')    // e.g., http://sonarqube:9000 (string credential)
    SONAR_TOKEN    = credentials('sonar-token')       // Secret text credential with the token
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build & Test') {
      steps { sh 'mvn -B -q -DskipTests=false clean verify' }
      post {
        always {
          junit '**/target/surefire-reports/*.xml'
        }
      }
    }

    stage('SonarQube Analysis') {
      steps {
        sh """
          mvn -B -q sonar:sonar \
            -Dsonar.projectKey=hello-sonar-jenkins \
            -Dsonar.host.url=${SONAR_HOST_URL} \
            -Dsonar.login=${SONAR_TOKEN}
        """
      }
    }
  }
}
```

> In Jenkins → **Manage Jenkins → Credentials**, create:
>
> * **Secret text**: ID `sonar-token` → value = token printed by `init_sonar_admin_and_token.sh`.
> * **Secret text**: ID `sonar-host-url` → value `http://sonarqube:9000` (Jenkins resolves service by Docker network name).

---

# 8) `README.md`

````markdown
# SonarQube + Jenkins + Maven (Docker Compose)

A batteries-included local CI code quality stack for rapid demos and training.

## What’s inside
- **PostgreSQL 15** for SonarQube
- **SonarQube Community** (port 9000)
- **Jenkins LTS (JDK 17)** with essential plugins (Git, Pipeline, Sonar, Docker, etc.)
- **Maven 3.9** helper container and Jenkins Docker agent usage
- Persisted volumes for DB, Sonar data, Jenkins home, and Maven repo

## Prerequisites
- Docker engine + Docker Compose plugin
- 4 GB+ RAM free (SonarQube likes memory)
- Linux/macOS/Windows (WSL2 ok)

## Quick start (local)
```bash
cp .env.example .env
docker-compose up -d
````

* Jenkins → [http://localhost:8080](http://localhost:8080)
* SonarQube → [http://localhost:9000](http://localhost:9000)

Get Jenkins initial admin password:

```bash
./scripts/jenkins_admin_password.sh
```

## First-time Sonar setup (optional automation)

Change default password `admin/admin` and create a token:

```bash
export SONARQUBE_HOST=http://localhost:9000
export SONARQUBE_ADMIN_NEW_PASSWORD='ChangeMe123!'
export SONARQUBE_TOKEN_NAME='jenkins-token'
./scripts/init_sonar_admin_and_token.sh
```

**Save the printed `SONAR_TOKEN`** as a Jenkins **Secret text** credential with ID `sonar-token`.
Create another **Secret text** with ID `sonar-host-url` and value `http://sonarqube:9000`.

## Run the sample pipeline

1. In Jenkins, create a Multibranch (or Pipeline) job pointing to this repo.
2. Build the branch containing `/sample-app/Jenkinsfile`.
3. The pipeline will: checkout → build/test with Maven → run **SonarQube** analysis.
4. View quality reports in SonarQube.

## Amazon Linux one-command setup

From a fresh Amazon Linux 2023 EC2 (t3.large recommended):

```bash
curl -fsSL https://raw.githubusercontent.com/<your-gh-user>/sonarqube-jenkins-maven-docker-suite/main/scripts/install_amazon_linux.sh -o install.sh
bash install.sh
# Re-login or 'newgrp docker' after the script to use docker without sudo
```

Open:

* Jenkins: `http://<EC2-Public-IP>:8080`
* SonarQube: `http://<EC2-Public-IP>:9000`

## Tuning & notes

* SonarQube requires `vm.max_map_count=262144`. The install script sets this via `/etc/sysctl.conf`.
* For low-memory hosts, you may set `SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true` (already set in compose) but aim to allocate adequate memory for stable use.
* Jenkins uses host Docker via `/var/run/docker.sock` so you can build images in pipelines if needed.

## Common commands

```bash
docker-compose ps
docker-compose logs -f sonarqube
docker-compose logs -f jenkins
docker-compose down
docker volume ls
```

## Security

This is a demo/dev stack. For production:

* Externalize secrets (no tokens in env/files)
* Use TLS + reverse proxy
* Harden Docker daemon and Jenkins agents
* Backup volumes regularly

```

---

## How to use this answer
1) Copy the files into a new repo named **`sonarqube-jenkins-maven-docker-suite`**.  
2) Run the Amazon Linux script on your EC2 or run locally with Docker.  
3) Visit Jenkins & SonarQube, add the Sonar token to Jenkins credentials, and run the sample pipeline.

If you want, I can also add:
- Jenkins Configuration-as-Code (JCasC) to auto-register Sonar server & credentials,
- A multi-stage Docker build example for the sample app,
- A GitHub Actions workflow that mirrors the Jenkins pipeline.
```
