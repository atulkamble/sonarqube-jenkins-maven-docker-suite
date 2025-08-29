FROM jenkins/jenkins:lts-jdk17

# Pre-install Jenkins plugins (unchanged)
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

USER root

# Install Docker CLI and git (Debian-based image)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      docker.io git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Add Jenkins user to the docker group to use /var/run/docker.sock
RUN groupadd -f docker && usermod -aG docker jenkins

# Optional: a local dir for Maven cache shared with docker agents
RUN mkdir -p /var/maven/repo && chown -R jenkins:jenkins /var/maven/repo

USER jenkins
