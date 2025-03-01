#!/bin/bash

# Script pour corriger la connexion Adminer-MySQL lorsque le port MySQL n'est pas standard (3306)
# Usage: ./adminer-fix.sh

# Charger les variables d'environnement
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

MYSQL_PORT=${MYSQL_PORT:-3306}

# Créer un réseau pour que MySQL soit accessible par hostname:port
echo "Configuration pour permettre à Adminer de se connecter à MySQL sur le port $MYSQL_PORT..."

# Récupérer l'adresse IP du conteneur MySQL
MYSQL_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mysql_db)

if [ -z "$MYSQL_IP" ]; then
    echo "Erreur: Impossible de trouver l'adresse IP du conteneur MySQL"
    exit 1
fi

echo "Adresse IP du conteneur MySQL: $MYSQL_IP"

# Informations de connexion pour Adminer
echo ""
echo "============================================================="
echo "Pour vous connecter à MySQL depuis Adminer:"
echo "Système: MySQL"
echo "Serveur: $MYSQL_IP (ou utilisez 'mysql' si ça fonctionne)"
echo "Port: $MYSQL_PORT"
echo "Utilisateur: app_user (ou 'root' pour l'admin complet)"
echo "Mot de passe: [celui configuré dans votre fichier .env]"
echo "Base de données: [laissez vide pour voir toutes les bases]"
echo "============================================================="
echo ""
echo "Si vous modifiez le port MySQL dans le fichier .env, assurez-vous de:"
echo "1. Arrêter les conteneurs: docker-compose down"
echo "2. Redémarrer: docker-compose up -d"
echo "3. Exécuter ce script à nouveau: ./scripts/adminer-fix.sh"

exit 0