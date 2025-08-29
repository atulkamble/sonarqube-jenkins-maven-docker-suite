FROM jenkins/jenkins:lts-jdk17

# Pre-install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Preconfigure Maven Global Settings directory
USER root
RUN mkdir -p /var/maven/repo && chown -R jenkins:jenkins /var/maven/repo
USER jenkins
