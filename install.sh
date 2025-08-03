#!/bin/bash
set -e

echo "=== Installing Java, Jenkins, Docker, SonarQube, Trivy ==="
sudo apt update -y
sudo apt install -y openjdk-17-jdk openjdk-17-jre unzip curl gnupg lsb-release apt-transport-https wget docker.io

sudo usermod -aG docker jenkins
sudo usermod -aG docker ubuntu
sudo chmod 777 /var/run/docker.sock
sudo systemctl restart docker

# --- Jenkins Installation ---
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -y
sudo apt-get install jenkins -y


# Copy SonarQube
docker run -d --name sonar -p 9000:9000 sonarqube:lts-community
mkdir -p /home/ubuntu/pro

cat <<'EOF' > /home/ubuntu/pro/run.sh
#!/bin/bash
set -e

echo "=== Applying Jenkins Groovy Config ==="
sudo mkdir -p /var/lib/jenkins/init.groovy.d
sudo cp /opt/jenkins-bootstrap/basic-setup.groovy /var/lib/jenkins/init.groovy.d/
sudo chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d

echo "=== Restarting Jenkins ==="
sudo systemctl restart jenkins

echo "=== Waiting for Jenkins to be ready... ==="
until curl -s http://localhost:8080/login > /dev/null; do
  echo "Waiting..."
  sleep 5
done

echo "✅ Jenkins Groovy setup applied."
EOF

chmod +x /home/ubuntu/pro/run.sh
chown -R ubuntu:ubuntu /home/ubuntu/pro

cat <<'EOF' > /home/ubuntu/pro//basic-setup.groovy
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.jenkins.plugins.awscredentials.AWSCredentialsImpl
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret
import hudson.model.JDK
import hudson.plugins.sonar.SonarRunnerInstallation
import jenkins.plugins.nodejs.tools.NodeJSInstallation
import jenkins.plugins.nodejs.tools.NodeJSInstaller
import org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation
import hudson.plugins.sonar.SonarGlobalConfiguration
import hudson.plugins.sonar.SonarInstallation

// ---- CREATE ADMIN USER ----
def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
if (hudsonRealm.getAllUsers().size() == 0) {
    hudsonRealm.createAccount('sree', 'sree123')
    instance.setSecurityRealm(hudsonRealm)
}
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
instance.save()

// ---- ADD CREDENTIALS ----
def credentials_store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

// 1. Docker Hub (Username/Password)
def dockerCreds = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    "docker",
    "docker hub credentials for pipeline",
    "devopslearning25",
    "docker@aws123"
)
credentials_store.addCredentials(Domain.global(), dockerCreds)

// 2. Github Personal Access Token (Secret Text)
def githubToken = new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    "githubcred",
    "Github Personal Access Token",
    Secret.fromString("REPLACE_WITH_REAL_TOKEN")
)
credentials_store.addCredentials(Domain.global(), githubToken)

// 3. AWS Credentials (Access Key & Secret)
def awsCreds = new AWSCredentialsImpl(
    CredentialsScope.GLOBAL,
    "aws-key",
    "aws credentials for pipeline",
    "REPLACE_WITH_REAL_ACCESS_KEY",
    "REPLACE_WITH_REAL_SECRET_KEY"
)
credentials_store.addCredentials(Domain.global(), awsCreds)

// 4. SonarQube Token (Secret Text)
def sonarToken = new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    "sonar-token",
    "SonarQube Authentication Token",
    Secret.fromString("REPLACE_WITH_REAL_TOKEN")
)
credentials_store.addCredentials(Domain.global(), sonarToken)

// ------ Global Tool Installations ------

// JDK Installation
def jdkDesc = new JDK.DescriptorImpl()
def jdkInstall = new JDK("jdk", "/usr/lib/jvm/java-17-openjdk-amd64")
jdkDesc.setInstallations(jdkInstall)
jdkDesc.save()

// SonarQube Scanner Installation
def sonarRunnerDesc = Jenkins.instance.getDescriptorByType(SonarRunnerInstallation.DescriptorImpl.class)
def sonarInstall = new SonarRunnerInstallation("sonar-scanner", "", [new hudson.plugins.sonar.SonarRunnerInstaller(null)])
sonarRunnerDesc.setInstallations(sonarInstall)
sonarRunnerDesc.save()

// NodeJS Installation
def nodejsDesc = Jenkins.instance.getDescriptorByType(NodeJSInstallation.DescriptorImpl.class)
def nodejsInstall = new NodeJSInstallation("nodejs", "", [new NodeJSInstaller(null, "", false)])
nodejsDesc.setInstallations(nodejsInstall)
nodejsDesc.save()

// Dependency-Check Installation
def dcDesc = Jenkins.instance.getDescriptorByType(org.jenkinsci.plugins.DependencyCheck.tools.DependencyCheckInstallation.DescriptorImpl.class)
def dcInstall = new DependencyCheckInstallation("DP-Check", "/opt/owasp-dc/dependency-check", [])
dcDesc.setInstallations(dcInstall)
dcDesc.save()

// ------ SonarQube Server Configuration ------
def sonarConfig = Jenkins.instance.getDescriptorByType(hudson.plugins.sonar.SonarGlobalConfiguration.class)
def sonarServer = new SonarInstallation(
    "sonar-server",
    "http://44.213.89.155:9000/",
    "sonar-token", // Credential ID
    "",
    "",
    null,
    false
)
sonarConfig.setInstallations(sonarServer)
sonarConfig.save()
EOF

chmod +x /home/ubuntu/pro//basic-setup.groovy
chown -R ubuntu:ubuntu /home/ubuntu/pro


echo "Setup complete."
