#!/bin/bash

# Script de sauvegarde pour MySQL utilisant le conteneur Docker
# Utilisation: ./backup.sh [nom_base_de_données]

# Charger les variables d'environnement
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Vérifier si Docker est installé
if ! command -v docker &> /dev/null; then
    echo "Erreur: Docker n'est pas installé sur ce système"
    exit 1
fi

# Vérifier si le conteneur MySQL est en cours d'exécution
CONTAINER_NAME="mysql_db"
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo "Erreur: Le conteneur MySQL '$CONTAINER_NAME' n'est pas en cours d'exécution"
    exit 1
fi

# Date et heure pour le nom du fichier
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR=${MYSQL_BACKUP_DIR:-./backup}

# Créer le répertoire de sauvegarde s'il n'existe pas
mkdir -p $BACKUP_DIR

# Vérifier si une base de données spécifique a été fournie
if [ "$1" ]; then
    DB_NAME=$1
    BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"
    
    echo "Sauvegarde de la base de données $DB_NAME..."
    docker exec $CONTAINER_NAME mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} --single-transaction --quick --lock-tables=false $DB_NAME | gzip > $BACKUP_FILE
    
    if [ $? -eq 0 ]; then
        echo "Sauvegarde réussie: $BACKUP_FILE"
    else
        echo "Erreur lors de la sauvegarde de $DB_NAME"
        exit 1
    fi
else
    # Sauvegarder toutes les bases de données
    BACKUP_FILE="${BACKUP_DIR}/all_databases_${TIMESTAMP}.sql.gz"
    
    echo "Sauvegarde de toutes les bases de données..."
    docker exec $CONTAINER_NAME mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} --all-databases --single-transaction --quick --lock-tables=false | gzip > $BACKUP_FILE
    
    if [ $? -eq 0 ]; then
        echo "Sauvegarde de toutes les bases de données réussie: $BACKUP_FILE"
    else
        echo "Erreur lors de la sauvegarde des bases de données"
        exit 1
    fi
fi

# Nettoyage des sauvegardes anciennes (plus de 30 jours)
echo "Suppression des sauvegardes de plus de 30 jours..."
find $BACKUP_DIR -name "*.sql.gz" -type f -mtime +30 -delete

echo "Informations sur la sauvegarde:"
echo "  - Taille: $(du -h $BACKUP_FILE | awk '{print $1}')"
echo "  - Emplacement: $BACKUP_FILE"

exit 0