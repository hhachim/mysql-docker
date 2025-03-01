#!/bin/bash

# Script de restauration pour MySQL
# Utilisation: ./restore.sh fichier_sauvegarde.sql.gz [nom_base_de_données]

# Charger les variables d'environnement
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

BACKUP_DIR=${MYSQL_BACKUP_DIR:-./backup}

# Vérifier si un fichier de sauvegarde a été fourni
if [ -z "$1" ]; then
    echo "Erreur: Aucun fichier de sauvegarde spécifié"
    echo "Utilisation: $0 fichier_sauvegarde.sql.gz [nom_base_de_données]"
    exit 1
fi

BACKUP_FILE="$1"

# Vérifier si le fichier existe
if [[ ! -f "$BACKUP_FILE" && ! -f "${BACKUP_DIR}/${BACKUP_FILE}" ]]; then
    echo "Erreur: Le fichier $BACKUP_FILE n'existe pas"
    exit 1
fi

# Utiliser le chemin complet si le fichier est dans le répertoire de sauvegarde
if [[ ! -f "$BACKUP_FILE" && -f "${BACKUP_DIR}/${BACKUP_FILE}" ]]; then
    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
fi

# Vérifier si c'est un fichier gzip
if [[ "$BACKUP_FILE" == *.gz ]]; then
    CMD_PIPE="gunzip < $BACKUP_FILE"
else
    CMD_PIPE="cat $BACKUP_FILE"
fi

# Si une base de données spécifique est fournie, restaurer uniquement celle-ci
if [ "$2" ]; then
    DB_NAME=$2
    
    # Vérifier si la base de données existe, sinon la créer
    echo "Vérification de la base de données $DB_NAME..."
    mysql -h127.0.0.1 -P${MYSQL_PORT} -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    echo "Restauration de la base de données $DB_NAME à partir de $BACKUP_FILE..."
    eval "$CMD_PIPE" | mysql -h127.0.0.1 -P${MYSQL_PORT} -uroot -p${MYSQL_ROOT_PASSWORD} $DB_NAME
    
    if [ $? -eq 0 ]; then
        echo "Restauration réussie dans $DB_NAME"
    else
        echo "Erreur lors de la restauration dans $DB_NAME"
        exit 1
    fi
else
    # Restaurer toutes les bases de données
    echo "Restauration de toutes les bases de données à partir de $BACKUP_FILE..."
    eval "$CMD_PIPE" | mysql -h127.0.0.1 -P${MYSQL_PORT} -uroot -p${MYSQL_ROOT_PASSWORD}
    
    if [ $? -eq 0 ]; then
        echo "Restauration de toutes les bases de données réussie"
    else
        echo "Erreur lors de la restauration des bases de données"
        exit 1
    fi
fi

exit 0