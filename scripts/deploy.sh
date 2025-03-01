#!/bin/bash

# Script de déploiement pour MySQL Docker
# Doit être exécuté sur la VM Linux cible
# Utilisation: ./deploy.sh

set -e

echo "=== Déploiement de l'environnement MySQL Docker ==="
echo "Ce script va installer Docker, Docker Compose et configurer l'environnement MySQL"

# Vérification des privilèges
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root ou avec sudo"
  exit 1
fi

# Détection de la distribution Linux
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "Impossible de détecter la distribution Linux"
    exit 1
fi

echo "Distribution détectée: $DISTRO"

# Installation de Docker selon la distribution
install_docker() {
    echo "Installation de Docker..."
    case $DISTRO in
        ubuntu|debian)
            apt-get update
            apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        centos|rhel|fedora)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            systemctl start docker
            systemctl enable docker
            ;;
        *)
            echo "Distribution non supportée pour l'installation automatique de Docker"
            echo "Veuillez installer Docker manuellement: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac

    # Vérification de l'installation de Docker
    if ! command -v docker &> /dev/null; then
        echo "Erreur: Docker n'a pas été installé correctement"
        exit 1
    fi

    echo "Docker installé avec succès"
}

# Installation de Docker Compose
install_docker_compose() {
    echo "Installation de Docker Compose..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    
    # Si la commande précédente a échoué, utiliser une version par défaut
    if [ -z "$COMPOSE_VERSION" ]; then
        COMPOSE_VERSION="v2.20.2"
        echo "Impossible de détecter la dernière version, utilisation de la version par défaut: $COMPOSE_VERSION"
    fi
    
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o $DOCKER_CONFIG/cli-plugins/docker-compose
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

    # Vérification de l'installation
    if ! docker compose version &> /dev/null; then
        echo "Erreur: Docker Compose n'a pas été installé correctement"
        exit 1
    fi

    echo "Docker Compose installé avec succès"
}

# Configuration du projet
setup_project() {
    echo "Configuration du projet MySQL..."
    
    # Création des répertoires nécessaires
    mkdir -p data
    mkdir -p backup
    mkdir -p scripts
    mkdir -p mysql-config
    mkdir -p init-scripts
    
    # Attribution des permissions
    chmod +x scripts/*.sh
    
    # Vérification du fichier .env
    if [ ! -f .env ]; then
        echo "Le fichier .env n'existe pas. Veuillez créer et configurer ce fichier avant de continuer."
        exit 1
    fi
    
    echo "Configuration terminée"
}

# Configuration du firewall si nécessaire
configure_firewall() {
    echo "Configuration du firewall..."
    
    case $DISTRO in
        ubuntu|debian)
            if command -v ufw &> /dev/null; then
                ufw allow 3306/tcp
                ufw allow 8080/tcp
                echo "Ports 3306 et 8080 ouverts dans UFW"
            fi
            ;;
        centos|rhel|fedora)
            if command -v firewall-cmd &> /dev/null; then
                firewall-cmd --permanent --add-port=3306/tcp
                firewall-cmd --permanent --add-port=8080/tcp
                firewall-cmd --reload
                echo "Ports 3306 et 8080 ouverts dans firewalld"
            fi
            ;;
        *)
            echo "Configuration du firewall ignorée"
            ;;
    esac
}

# Démarrage des services
start_services() {
    echo "Démarrage des services Docker..."
    docker compose up -d
    
    if [ $? -eq 0 ]; then
        echo "Services démarrés avec succès"
    else
        echo "Erreur lors du démarrage des services"
        exit 1
    fi
    
    # Afficher l'état des services
    docker compose ps
}

# Exécution principale
echo "Début du déploiement..."

# Vérifier si Docker est déjà installé
if ! command -v docker &> /dev/null; then
    install_docker
else
    echo "Docker est déjà installé"
fi

# Vérifier si Docker Compose est déjà installé
if ! docker compose version &> /dev/null; then
    install_docker_compose
else
    echo "Docker Compose est déjà installé"
fi

# Configuration du projet
setup_project

# Configuration du firewall
configure_firewall

# Démarrage des services
start_services

echo "=== Déploiement terminé avec succès ==="
echo "MySQL est accessible sur le port 3306"
echo "Adminer est accessible sur http://$(hostname -I | awk '{print $1}'):8080"
echo ""
echo "Utilisez ces identifiants pour vous connecter à Adminer:"
source .env
echo "Serveur: mysql (ou localhost si la connexion échoue)"
echo "Port: ${MYSQL_PORT}"
echo "Utilisateur: root"
source .env
echo "Mot de passe: $MYSQL_ROOT_PASSWORD"
echo ""
echo "N'oubliez pas de sécuriser votre installation en:"
echo "1. Modifiant les mots de passe dans le fichier .env"
echo "2. Configurant correctement le firewall pour limiter l'accès"
echo "3. Configurant un accès HTTPS si nécessaire"

exit 0