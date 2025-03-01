#!/bin/bash

# Script de restauration pour MySQL utilisant le conteneur Docker
# Utilisation: ./restore.sh fichier_sauvegarde.sql.gz [nom_base_de_données]

# Charger les variables d'environnement
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Configuration
CONTAINER_NAME="mysql_db"
BACKUP_DIR=${MYSQL_BACKUP_DIR:-./backup}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-"root_password_secure_123"}
LOG_FILE="restore_$(date +%Y%m%d_%H%M%S).log"

# Rediriger les logs vers un fichier et la console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "====== SCRIPT DE RESTAURATION MYSQL ======"
echo "Date: $(date)"

# Vérifier si Docker est installé
if ! command -v docker &> /dev/null; then
    echo "Erreur: Docker n'est pas installé sur ce système"
    exit 1
fi

# Vérifier si le conteneur MySQL est en cours d'exécution
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo "Erreur: Le conteneur MySQL '$CONTAINER_NAME' n'est pas en cours d'exécution"
    exit 1
fi

# Vérifier si un fichier de sauvegarde a été fourni
if [ -z "$1" ]; then
    echo "Erreur: Aucun fichier de sauvegarde spécifié"
    echo "Utilisation: $0 fichier_sauvegarde.sql.gz [nom_base_de_données]"
    exit 1
fi

BACKUP_FILE="$1"

# Vérifier si le fichier existe
if [[ -f "$BACKUP_FILE" ]]; then
    echo "Fichier trouvé: $BACKUP_FILE"
elif [[ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]]; then
    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
    echo "Fichier trouvé dans le répertoire des sauvegardes: $BACKUP_FILE"
else
    echo "Erreur: Le fichier $BACKUP_FILE n'existe pas"
    exit 1
fi

# Préparation pour restauration
if [[ "$BACKUP_FILE" == *.gz ]]; then
    DECOMPRESS_CMD="gunzip -c"
    echo "Fichier compressé détecté, utilisation de gunzip"
else
    DECOMPRESS_CMD="cat"
    echo "Fichier SQL non-compressé détecté"
fi

# Extraire les noms des bases de données de la sauvegarde
echo "Analyse du fichier de sauvegarde pour identifier les bases de données..."
DB_NAMES=$($DECOMPRESS_CMD "$BACKUP_FILE" | grep -E "^-- Current Database:" | awk '{print $4}' | tr -d '`' | sort -u)

if [ -z "$DB_NAMES" ]; then
    echo "Aucune base de données n'a pu être identifiée dans le fichier de sauvegarde avec le format standard."
    # Essayons une autre méthode
    DB_NAMES=$($DECOMPRESS_CMD "$BACKUP_FILE" | grep -E "^USE" | awk '{print $2}' | tr -d '`;' | sort -u)
    
    if [ -z "$DB_NAMES" ]; then
        echo "Aucune base de données n'a pu être identifiée avec la méthode alternative."
        echo "La restauration va continuer mais pourrait ne pas recréer automatiquement les bases manquantes."
    fi
fi

if [ -n "$DB_NAMES" ]; then
    echo "Bases de données identifiées dans la sauvegarde:"
    for DB in $DB_NAMES; do
        echo " - $DB"
        
        # Nous ignorons 'mysql', 'sys', 'performance_schema' et 'information_schema'
        if [[ "$DB" != "mysql" && "$DB" != "information_schema" && "$DB" != "performance_schema" && "$DB" != "sys" ]]; then
            # Créer les bases de données manquantes
            echo "Création de la base $DB si elle n'existe pas..."
            docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS \`$DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        else
            echo "Base système $DB ignorée pour la création"
        fi
    done
fi

# Si une base de données spécifique est fournie, restaurer uniquement celle-ci
if [ "$2" ]; then
    DB_NAME=$2
    
    # Vérifier si la base de données existe, sinon la créer
    echo "Vérification de la base de données $DB_NAME..."
    docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    echo "Restauration de la base de données $DB_NAME à partir de $BACKUP_FILE..."
    
    # Méthode 1: Utiliser mysqldump pour extraire seulement la base spécifique
    # Cette méthode est plus fiable mais nécessite que mysqldump soit disponible
    if command -v mysqldump &> /dev/null && [[ "$BACKUP_FILE" != *.gz ]]; then
        echo "Utilisation de mysqldump pour extraire les données de $DB_NAME..."
        $DECOMPRESS_CMD "$BACKUP_FILE" | grep -v "^USE" | docker exec -i $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} $DB_NAME
    else
        # Méthode 2: Restaurer tout le fichier et espérer que les bases sont correctement séparées
        echo "Restauration complète du fichier dans $DB_NAME..."
        $DECOMPRESS_CMD "$BACKUP_FILE" | docker exec -i $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} $DB_NAME
    fi
    
    RESTORE_STATUS=$?
    
    # Vérifier le résultat
    if [ $RESTORE_STATUS -eq 0 ]; then
        echo "✅ Restauration terminée avec succès dans $DB_NAME!"
        
        # Afficher les tables
        echo "Tables dans $DB_NAME:"
        docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW TABLES FROM \`$DB_NAME\`;"
        
        # Compter les tables
        TABLE_COUNT=$(docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SELECT COUNT(TABLE_NAME) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB_NAME';" -sN)
        echo "Nombre de tables: $TABLE_COUNT"
    else
        echo "❌ Erreur lors de la restauration dans $DB_NAME (code: $RESTORE_STATUS)"
    fi
else
    # Restaurer toutes les bases de données
    echo "Préparation pour la restauration complète..."
    
    # Lister les bases avant restauration
    echo "Bases de données avant restauration:"
    BEFORE_DBS=$(docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES;" | grep -v "Database\|information_schema\|performance_schema\|mysql\|sys")
    echo "$BEFORE_DBS"
    
    echo "Restauration de toutes les bases de données..."
    $DECOMPRESS_CMD "$BACKUP_FILE" | docker exec -i $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD}
    RESTORE_STATUS=$?
    
    # Vérifier le résultat
    if [ $RESTORE_STATUS -eq 0 ]; then
        echo "✅ Restauration complète terminée avec succès!"
        
        # Lister les bases après restauration
        echo "Bases de données après restauration:"
        AFTER_DBS=$(docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES;" | grep -v "Database\|information_schema\|performance_schema\|mysql\|sys")
        echo "$AFTER_DBS"
        
        # Comparer pour voir ce qui a été ajouté
        for DB in $AFTER_DBS; do
            if ! echo "$BEFORE_DBS" | grep -q "$DB"; then
                echo " - Nouvelle base de données restaurée: $DB"
            fi
        done
        
        # Afficher le nombre de tables pour chaque base
        for DB in $AFTER_DBS; do
            TABLE_COUNT=$(docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SELECT COUNT(TABLE_NAME) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB';" -sN)
            echo " - $DB: $TABLE_COUNT tables"
        done
    else
        echo "❌ Erreur lors de la restauration complète (code: $RESTORE_STATUS)"
    fi
fi

echo "Log de restauration disponible dans $LOG_FILE"
exit $RESTORE_STATUS