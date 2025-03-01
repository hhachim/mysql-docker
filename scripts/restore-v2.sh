#!/bin/bash

# Script amélioré de restauration pour MySQL utilisant Docker
# Utilisation: ./restore.sh [options] fichier_sauvegarde.sql.gz
#
# Options:
#   --db=NOM_BASE             Base de données cible (optionnel)
#   --preview                 Afficher le contenu sans restaurer
#   --dry-run                 Simuler la restauration sans l'exécuter
#   --table=NOM_TABLE         Restaurer uniquement une table spécifique
#   --to-temp                 Restaurer dans une base temporaire pour validation
#   --structure-only          Restaurer uniquement la structure (sans données)
#   --interactive             Mode interactif pour sélection de fichier
#   --decrypt                 Déchiffrer une sauvegarde chiffrée

# Charger les variables d'environnement
if [ -f .env ]; then
    source .env
fi

# Configuration par défaut
CONTAINER_NAME="mysql_db"
BACKUP_DIR=${MYSQL_BACKUP_DIR:-./backup}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-"root_password_secure_123"}
TMP_DIR="/tmp/mysql_restore_$$"
LOG_FILE="restore_$(date +%Y%m%d_%H%M%S).log"
TEMP_DB_PREFIX="temp_restore_"

# Traitement des options
PREVIEW=false
DRY_RUN=false
INTERACTIVE=false
STRUCTURE_ONLY=false
TO_TEMP=false
DECRYPT=false
TARGET_DB=""
TARGET_TABLE=""
BACKUP_FILE=""

# Fonction pour l'aide
show_help() {
    echo "Script amélioré de restauration MySQL"
    echo
    echo "Utilisation: $0 [options] fichier_sauvegarde.sql.gz"
    echo
    echo "Options:"
    echo "  --db=NOM_BASE             Base de données cible (optionnel)"
    echo "  --preview                 Afficher le contenu sans restaurer"
    echo "  --dry-run                 Simuler la restauration sans l'exécuter"
    echo "  --table=NOM_TABLE         Restaurer uniquement une table spécifique"
    echo "  --to-temp                 Restaurer dans une base temporaire pour validation"
    echo "  --structure-only          Restaurer uniquement la structure (sans données)"
    echo "  --interactive             Mode interactif pour sélection de fichier"
    echo "  --decrypt                 Déchiffrer une sauvegarde chiffrée"
    echo "  --help                    Afficher cette aide"
    echo
    echo "Exemples:"
    echo "  $0 --preview backup/all_databases_20250301.sql.gz"
    echo "  $0 --db=application_db backup/application_db_20250301.sql.gz"
    echo "  $0 --interactive"
    echo "  $0 --to-temp --db=application_db backup/all_databases_20250301.sql.gz"
    exit 0
}

# Fonction de journalisation
log() {
    local level=$1
    local message=$2
    local color=""
    local reset="\033[0m"
    
    case $level in
        "INFO")
            color="\033[0;32m" # Vert
            ;;
        "WARN")
            color="\033[0;33m" # Jaune
            ;;
        "ERROR")
            color="\033[0;31m" # Rouge
            ;;
        *)
            color="\033[0m" # Défaut
            ;;
    esac
    
    echo -e "${color}[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message${reset}" | tee -a "$LOG_FILE"
}

# Analyse des arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                ;;
            --db=*)
                TARGET_DB="${1#*=}"
                shift
                ;;
            --table=*)
                TARGET_TABLE="${1#*=}"
                shift
                ;;
            --preview)
                PREVIEW=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --interactive)
                INTERACTIVE=true
                shift
                ;;
            --to-temp)
                TO_TEMP=true
                shift
                ;;
            --structure-only)
                STRUCTURE_ONLY=true
                shift
                ;;
            --decrypt)
                DECRYPT=true
                shift
                ;;
            *)
                if [[ -z "$BACKUP_FILE" ]]; then
                    BACKUP_FILE="$1"
                else
                    log "ERROR" "Argument non reconnu: $1"
                    show_help
                fi
                shift
                ;;
        esac
    done
}

# Vérification des dépendances
check_dependencies() {
    local missing_deps=0
    
    log "INFO" "Vérification des dépendances..."
    
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker n'est pas installé"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! docker ps &> /dev/null; then
        log "ERROR" "Le service Docker n'est pas démarré ou vous n'avez pas les permissions nécessaires"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! docker ps | grep -q $CONTAINER_NAME; then
        log "ERROR" "Le conteneur MySQL '$CONTAINER_NAME' n'est pas en cours d'exécution"
        missing_deps=$((missing_deps + 1))
    fi
    
    if $DECRYPT && ! command -v gpg &> /dev/null; then
        log "ERROR" "GPG n'est pas installé (nécessaire pour --decrypt)"
        missing_deps=$((missing_deps + 1))
    fi
    
    if [ $missing_deps -gt 0 ]; then
        log "ERROR" "$missing_deps dépendance(s) manquante(s). Impossible de continuer."
        exit 1
    fi
    
    log "INFO" "Toutes les dépendances sont présentes."
}

# Vérification de l'espace disque
check_disk_space() {
    log "INFO" "Vérification de l'espace disque..."
    
    # Obtenir la taille du fichier de sauvegarde (compatible macOS et Linux)
    local file_size=0
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        file_size=$(stat -f %z "$BACKUP_FILE" 2>/dev/null)
    else
        # Linux
        file_size=$(stat -c %s "$BACKUP_FILE" 2>/dev/null)
    fi
    
    # Convertir en MB
    file_size=$((file_size / 1024 / 1024))
    
    # Facteur de sécurité: prévoir 3x la taille du fichier compressé
    local required_space=$((file_size * 3))
    
    # Vérifier l'espace disponible dans /tmp et le répertoire courant (compatible macOS et Linux)
    local tmp_space=0
    local curr_space=0
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        tmp_space=$(df -m /tmp | tail -1 | awk '{print $4}')
        curr_space=$(df -m . | tail -1 | awk '{print $4}')
    else
        # Linux
        tmp_space=$(df -BM /tmp | tail -1 | awk '{print $4}' | sed 's/M//')
        curr_space=$(df -BM . | tail -1 | awk '{print $4}' | sed 's/M//')
    fi
    
    log "INFO" "Taille de la sauvegarde: ${file_size}MB, espace requis: environ ${required_space}MB"
    log "INFO" "Espace disponible: ${tmp_space}MB dans /tmp, ${curr_space}MB dans le répertoire courant"
    
    # Protection contre les valeurs vides
    if [ -n "$tmp_space" ] && [ -n "$required_space" ] && [ "$tmp_space" -lt "$required_space" ]; then
        log "WARN" "Espace insuffisant dans /tmp. La restauration pourrait échouer."
    fi
    
    if [ -n "$curr_space" ] && [ -n "$required_space" ] && [ "$curr_space" -lt "$required_space" ]; then
        log "WARN" "Espace insuffisant dans le répertoire courant. La restauration pourrait échouer."
    fi
}

# Sélection interactive du fichier de sauvegarde
select_backup_file() {
    log "INFO" "Mode interactif: sélection du fichier de sauvegarde"
    
    # Trouver tous les fichiers de sauvegarde
    local backup_files=($(find $BACKUP_DIR -type f -name "*.sql*" | sort -r))
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        log "ERROR" "Aucun fichier de sauvegarde trouvé dans $BACKUP_DIR"
        exit 1
    fi
    
    echo "Fichiers de sauvegarde disponibles:"
    for i in "${!backup_files[@]}"; do
        local file="${backup_files[$i]}"
        local size=$(du -h "$file" | awk '{print $1}')
        local date=$(stat -c %y "$file" 2>/dev/null || stat -f "%Sm" "$file")
        echo "$((i+1)). $(basename "$file") ($size, $date)"
    done
    
    local selection
    read -p "Sélectionnez un fichier (1-${#backup_files[@]}): " selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#backup_files[@]} ]; then
        log "ERROR" "Sélection invalide"
        exit 1
    fi
    
    BACKUP_FILE="${backup_files[$((selection-1))]}"
    log "INFO" "Fichier sélectionné: $BACKUP_FILE"
}

# Préparation du fichier de sauvegarde
prepare_backup_file() {
    log "INFO" "Préparation du fichier de sauvegarde: $BACKUP_FILE"
    
    # Créer le répertoire temporaire
    mkdir -p "$TMP_DIR"
    
    # Vérifier si le fichier existe
    if [[ -f "$BACKUP_FILE" ]]; then
        log "INFO" "Fichier trouvé: $BACKUP_FILE"
    elif [[ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]]; then
        BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
        log "INFO" "Fichier trouvé dans le répertoire des sauvegardes: $BACKUP_FILE"
    else
        log "ERROR" "Le fichier $BACKUP_FILE n'existe pas"
        exit 1
    fi
    
    # Vérifier les permissions
    if [ ! -r "$BACKUP_FILE" ]; then
        log "ERROR" "Impossible de lire le fichier $BACKUP_FILE (problème de permissions)"
        exit 1
    fi
    
    # Vérifier si c'est un fichier chiffré
    if [[ "$BACKUP_FILE" == *.gpg ]]; then
        if ! $DECRYPT; then
            log "ERROR" "Le fichier est chiffré. Utilisez l'option --decrypt pour continuer."
            exit 1
        fi
        
        log "INFO" "Déchiffrement du fichier..."
        if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
            read -s -p "Entrez la phrase de passe pour déchiffrer: " BACKUP_ENCRYPTION_KEY
            echo
        fi
        
        local decrypted_file="${TMP_DIR}/$(basename "$BACKUP_FILE" .gpg)"
        gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
            --decrypt -o "$decrypted_file" "$BACKUP_FILE"
            
        if [ $? -ne 0 ]; then
            log "ERROR" "Échec du déchiffrement"
            exit 1
        fi
        
        BACKUP_FILE="$decrypted_file"
        log "INFO" "Déchiffrement réussi: $BACKUP_FILE"
    fi
    
    # Déterminer la méthode de décompression
    local extracted_file
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        DECOMPRESS_CMD="gunzip -c"
        extracted_file="${TMP_DIR}/$(basename "$BACKUP_FILE" .gz)"
        log "INFO" "Fichier gzip détecté"
    elif [[ "$BACKUP_FILE" == *.xz ]]; then
        DECOMPRESS_CMD="xz -dc"
        extracted_file="${TMP_DIR}/$(basename "$BACKUP_FILE" .xz)"
        log "INFO" "Fichier xz détecté"
    else
        DECOMPRESS_CMD="cat"
        extracted_file="${TMP_DIR}/$(basename "$BACKUP_FILE")"
        log "INFO" "Fichier SQL non compressé détecté"
    fi
    
    # Si on a besoin d'analyser ou modifier le fichier, décompresser d'abord
    if $PREVIEW || $STRUCTURE_ONLY || [ -n "$TARGET_TABLE" ]; then
        log "INFO" "Décompression pour analyse..."
        $DECOMPRESS_CMD "$BACKUP_FILE" > "$extracted_file"
        if [ $? -ne 0 ]; then
            log "ERROR" "Échec de la décompression"
            exit 1
        fi
        BACKUP_FILE="$extracted_file"
        DECOMPRESS_CMD="cat" # Maintenant c'est un fichier texte normal
    fi
}

# Analyse du fichier de sauvegarde
analyze_backup() {
    log "INFO" "Analyse du fichier de sauvegarde..."
    
    # Détecter si nous devons décompresser pour l'analyse
    if [[ "$BACKUP_FILE" == *.gz && "$DECOMPRESS_CMD" != "cat" ]]; then
        log "INFO" "Décompression temporaire pour analyser le contenu..."
        local temp_file="${TMP_DIR}/temp_for_analysis.sql"
        gunzip -c "$BACKUP_FILE" > "$temp_file"
        local file_to_analyze="$temp_file"
    else
        local file_to_analyze="$BACKUP_FILE"
    fi
    
    # Extraire les noms des bases de données avec des méthodes compatibles macOS et Linux
    log "INFO" "Recherche des bases de données dans le fichier..."
    
    # Méthode 1: Chercher les lignes "Current Database" (format mysqldump)
    local dbs_method1=$(grep "^-- Current Database:" "$file_to_analyze" | 
                      grep -v "mysql\|information_schema\|performance_schema\|sys" |
                      sed 's/^-- Current Database: `\(.*\)`/\1/')
    
    # Méthode 2: Chercher les instructions USE
    local dbs_method2=$(grep "^USE " "$file_to_analyze" | 
                      grep -v "mysql\|information_schema\|performance_schema\|sys" |
                      sed 's/^USE `\{0,1\}\([^`]*\)`\{0,1\};/\1/')
    
    # Méthode 3: Chercher les CREATE DATABASE
    local dbs_method3=$(grep "CREATE DATABASE" "$file_to_analyze" | 
                      grep -v "mysql\|information_schema\|performance_schema\|sys" |
                      sed 's/.*`\([^`]*\)`.*/\1/')
    
    # Combiner les résultats
    DB_NAMES=$(echo -e "$dbs_method1\n$dbs_method2\n$dbs_method3" | grep -v "^$" | sort -u)
    
    # Si c'était un fichier temporaire, le supprimer
    if [[ "$file_to_analyze" != "$BACKUP_FILE" ]]; then
        rm -f "$file_to_analyze"
    fi
    
    if [ -z "$DB_NAMES" ]; then
        log "WARN" "Aucune base de données identifiée dans le fichier de sauvegarde"
        
        # Essayer une méthode de secours pour les fichiers mysqldump
        local has_tables=$(grep "CREATE TABLE" "$BACKUP_FILE" | wc -l)
        if [ "$has_tables" -gt 0 ]; then
            log "INFO" "Le fichier contient des tables mais les bases de données n'ont pas été identifiées"
        fi
        
        # Si TARGET_DB est spécifié, on l'utilise malgré tout
        if [ -n "$TARGET_DB" ]; then
            DB_NAMES="$TARGET_DB"
            log "INFO" "Utilisation de la base cible spécifiée: $TARGET_DB"
        else
            log "ERROR" "Impossible de déterminer la base de données à restaurer"
            log "ERROR" "Veuillez spécifier une base cible avec l'option --db"
            exit 1
        fi
    else
        log "INFO" "Bases de données identifiées: $DB_NAMES"
    fi
    
    # Si TARGET_TABLE est spécifié, vérifier qu'il existe dans la sauvegarde
    if [ -n "$TARGET_TABLE" ]; then
        if ! grep -q "CREATE TABLE.*\`$TARGET_TABLE\`" "$BACKUP_FILE"; then
            log "ERROR" "La table '$TARGET_TABLE' n'existe pas dans la sauvegarde"
            exit 1
        fi
        log "INFO" "Table '$TARGET_TABLE' trouvée dans la sauvegarde"
    fi
}

# Prévisualisation du contenu
preview_backup() {
    log "INFO" "Prévisualisation du contenu de la sauvegarde..."
    
    echo "----- APERÇU DU CONTENU DE LA SAUVEGARDE -----"
    echo
    
    # Afficher les bases et tables disponibles
    echo "Bases de données:"
    echo "$DB_NAMES" | sed 's/^/  - /'
    echo
    
    # Extraire et afficher la structure des tables
    echo "Tables par base de données:"
    for db in $DB_NAMES; do
        echo "  $db:"
        grep -A 1 "CREATE TABLE.*\`$db\`" "$BACKUP_FILE" | 
        grep -oP "CREATE TABLE.*\`$db\`\.?\`\K[^\`]*" | 
        sort | sed 's/^/    - /'
    done
    echo
    
    # Aperçu des procédures stockées et triggers
    PROCEDURES=$(grep -c "CREATE.*PROCEDURE" "$BACKUP_FILE")
    FUNCTIONS=$(grep -c "CREATE.*FUNCTION" "$BACKUP_FILE")
    TRIGGERS=$(grep -c "CREATE.*TRIGGER" "$BACKUP_FILE")
    EVENTS=$(grep -c "CREATE.*EVENT" "$BACKUP_FILE")
    
    echo "Objets de base de données:"
    echo "  - Procédures stockées: $PROCEDURES"
    echo "  - Fonctions: $FUNCTIONS"
    echo "  - Déclencheurs: $TRIGGERS"
    echo "  - Événements: $EVENTS"
    echo
    
    # Afficher la taille totale
    echo "Taille totale de la sauvegarde: $(du -h "$BACKUP_FILE" | awk '{print $1}')"
    echo
    
    # Chercher des potentiels problèmes
    echo "Avertissements potentiels:"
    if grep -q "DEFINER=" "$BACKUP_FILE"; then
        echo "  - Contient des DEFINER qui peuvent causer des problèmes de permission"
    fi
    
    if grep -q "ROW_FORMAT=COMPRESSED" "$BACKUP_FILE"; then
        echo "  - Contient des tables avec ROW_FORMAT=COMPRESSED qui nécessitent une configuration spécifique"
    fi
    
    echo "----- FIN DE L'APERÇU -----"
}

# Préparation de la base de données cible
prepare_target_database() {
    # Si aucune base cible n'est spécifiée mais qu'une seule base est dans la sauvegarde
    if [ -z "$TARGET_DB" ] && [ $(echo "$DB_NAMES" | wc -l) -eq 1 ]; then
        TARGET_DB=$(echo "$DB_NAMES" | tr -d '[:space:]')
        log "INFO" "Base cible auto-détectée: $TARGET_DB"
    fi
    
    # Si --to-temp est spécifié, créer une base temporaire
    if $TO_TEMP; then
        if [ -z "$TARGET_DB" ]; then
            log "ERROR" "L'option --to-temp nécessite une base cible spécifiée avec --db"
            exit 1
        fi
        
        ORIGINAL_TARGET_DB="$TARGET_DB"
        TARGET_DB="${TEMP_DB_PREFIX}${TARGET_DB}_$(date +%s)"
        log "INFO" "Restauration dans une base temporaire: $TARGET_DB"
        
        # Créer la base temporaire
        log "INFO" "Création de la base temporaire..."
        if ! $DRY_RUN; then
            docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} \
                -e "CREATE DATABASE IF NOT EXISTS \`$TARGET_DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
            
            if [ $? -ne 0 ]; then
                log "ERROR" "Échec de la création de la base temporaire"
                exit 1
            fi
        fi
    elif [ -n "$TARGET_DB" ]; then
        # Vérifier si la base existe déjà
        if ! $DRY_RUN; then
            DB_EXISTS=$(docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} \
                -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$TARGET_DB';" | 
                grep -c "$TARGET_DB")
            
            if [ "$DB_EXISTS" -eq 0 ]; then
                log "INFO" "La base '$TARGET_DB' n'existe pas, création..."
                docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} \
                    -e "CREATE DATABASE \`$TARGET_DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
            else
                log "WARN" "La base '$TARGET_DB' existe déjà. La restauration écrasera les données existantes."
                read -p "Continuer? (o/n): " confirm
                if [[ "$confirm" != "o" && "$confirm" != "O" && "$confirm" != "oui" ]]; then
                    log "INFO" "Restauration abandonnée à la demande de l'utilisateur"
                    exit 0
                fi
            fi
        fi
    fi
}

# Préparer un fichier SQL modifié si nécessaire
prepare_sql_file() {
    local modified_file="${TMP_DIR}/modified_backup.sql"
    
    # Si on restaure uniquement la structure
    if $STRUCTURE_ONLY; then
        log "INFO" "Préparation d'un fichier SQL avec uniquement la structure..."
        
        # Extraction de la structure uniquement
        grep -v "^INSERT INTO" "$BACKUP_FILE" > "$modified_file"
        
        # Vérifier que le fichier n'est pas vide
        if [ ! -s "$modified_file" ]; then
            log "ERROR" "Le fichier de structure est vide, quelque chose s'est mal passé"
            exit 1
        fi
        
        BACKUP_FILE="$modified_file"
        log "INFO" "Fichier de structure préparé: $(du -h "$BACKUP_FILE" | awk '{print $1}')"
    fi
    
    # Si on restaure une table spécifique
    if [ -n "$TARGET_TABLE" ]; then
        log "INFO" "Préparation d'un fichier SQL avec uniquement la table '$TARGET_TABLE'..."
        
        # Trouver les lignes de création et d'insertion pour cette table
        awk -v table="$TARGET_TABLE" '
            # Capture le début du block CREATE TABLE
            /CREATE TABLE.*`'"$TARGET_TABLE"'`/ {
                print_table = 1
                buffer = $0 "\n"
                next
            }
            
            # Si on est dans un block CREATE TABLE
            print_table == 1 {
                buffer = buffer $0 "\n"
                if (/;$/) {  # Fin de la définition de table
                    print buffer
                    buffer = ""
                    print_table = 0
                }
            }
            
            # Capture toutes les lignes INSERT INTO pour cette table
            /INSERT INTO.*`'"$TARGET_TABLE"'`/ {
                print
            }
        ' "$BACKUP_FILE" > "$modified_file"
        
        # Vérifier que le fichier n'est pas vide
        if [ ! -s "$modified_file" ]; then
            log "ERROR" "Le fichier pour la table '$TARGET_TABLE' est vide, vérifiez le nom de la table"
            exit 1
        fi
        
        BACKUP_FILE="$modified_file"
        log "INFO" "Fichier pour la table '$TARGET_TABLE' préparé: $(du -h "$BACKUP_FILE" | awk '{print $1}')"
    fi
}

# Restauration de la base de données
restore_database() {
    log "INFO" "Début de la restauration..."
    
    if $DRY_RUN; then
        log "INFO" "Mode simulation: aucune restauration ne sera effectuée"
        echo "Commande qui serait exécutée:"
        echo "$DECOMPRESS_CMD \"$BACKUP_FILE\" | docker exec -i $CONTAINER_NAME mysql -uroot -p******* ${TARGET_DB:+$TARGET_DB}"
        return 0
    fi
    
    # Démarrer un timer pour mesurer la durée
    local start_time=$(date +%s)
    
    log "INFO" "Restauration en cours... (cela peut prendre un certain temps)"
    
    # Exécution de la restauration avec une barre de progression
    local pid
    (
        # Si TARGET_DB est spécifié, restaurer dans cette base
        if [ -n "$TARGET_DB" ]; then
            $DECOMPRESS_CMD "$BACKUP_FILE" | docker exec -i $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} $TARGET_DB
        else
            # Sinon, restauration complète
            $DECOMPRESS_CMD "$BACKUP_FILE" | docker exec -i $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD}
        fi
    ) &
    pid=$!
    
    # Afficher une barre de progression
    local spin=('-' '\' '|' '/')
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        echo -ne "\rRestauration en cours... ${spin[$i]}"
        sleep 0.5
    done
    echo -e "\rRestauration terminée!       "
    
    # Attendre la fin du processus et récupérer le code de retour
    wait $pid
    local restore_status=$?
    
    # Calculer la durée
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $restore_status -eq 0 ]; then
        log "INFO" "Restauration terminée avec succès en ${duration}s"
        
        # Afficher des informations sur la base restaurée
        if [ -n "$TARGET_DB" ]; then
            log "INFO" "Détails de la base restaurée: $TARGET_DB"
            
            # Compter les tables
            local table_count=$(docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} \
                -e "SELECT COUNT(TABLE_NAME) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$TARGET_DB';" -sN)
            
            log "INFO" "Nombre de tables: $table_count"
            
            # Si --to-temp, demander si on veut remplacer la base originale
            if $TO_TEMP; then
                echo
                echo "La base temporaire '$TARGET_DB' a été créée avec succès."
                echo "Vous pouvez maintenant vérifier son contenu via Adminer ou en ligne de commande."
                echo
                read -p "Voulez-vous remplacer la base '$ORIGINAL_TARGET_DB' par cette base temporaire? (o/n): " replace
                
                if [[ "$replace" == "o" || "$replace" == "O" || "$replace" == "oui" ]]; then
                    log "INFO" "Remplacement de '$ORIGINAL_TARGET_DB' par '$TARGET_DB'..."
                    
                    # Supprimer l'ancienne base et renommer la temporaire
                    docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} \
                        -e "DROP DATABASE IF EXISTS \`$ORIGINAL_TARGET_DB\`; 
                            CREATE DATABASE \`$ORIGINAL_TARGET_DB\`; 
                            
                            /* Copier tous les objets de la base temporaire vers la base originale */
                            SET @tables = NULL;
                            SET @views = NULL;
                            SET @routines = NULL;
                            SET @triggers = NULL;
                            SET @events = NULL;
                            
                            /* Identifier les tables */
                            SELECT GROUP_CONCAT(TABLE_NAME) INTO @tables 
                            FROM information_schema.TABLES 
                            WHERE TABLE_SCHEMA = '$TARGET_DB' AND TABLE_TYPE = 'BASE TABLE';
                            
                            /* Identifier les vues */
                            SELECT GROUP_CONCAT(TABLE_NAME) INTO @views 
                            FROM information_schema.TABLES 
                            WHERE TABLE_SCHEMA = '$TARGET_DB' AND TABLE_TYPE = 'VIEW';
                            
                            /* Identifier les routines */
                            SELECT GROUP_CONCAT(ROUTINE_NAME) INTO @routines 
                            FROM information_schema.ROUTINES 
                            WHERE ROUTINE_SCHEMA = '$TARGET_DB';
                            
                            /* Identifier les triggers */
                            SELECT GROUP_CONCAT(TRIGGER_NAME) INTO @triggers 
                            FROM information_schema.TRIGGERS 
                            WHERE TRIGGER_SCHEMA = '$TARGET_DB';
                            
                            /* Identifier les events */
                            SELECT GROUP_CONCAT(EVENT_NAME) INTO @events 
                            FROM information_schema.EVENTS 
                            WHERE EVENT_SCHEMA = '$TARGET_DB';
                            
                            /* Copier les objets */
                            SET @query = CONCAT('RENAME TABLE ', 
                                                IF(@tables IS NOT NULL, 
                                                   REPLACE(CONCAT('$TARGET_DB.', @tables), ',', ' TO $ORIGINAL_TARGET_DB., $TARGET_DB.'), 
                                                   ''), 
                                                ' TO $ORIGINAL_TARGET_DB.;');
                            
                            /* Exécuter la requête si des tables existent */
                            IF @tables IS NOT NULL THEN
                                PREPARE stmt FROM @query;
                                EXECUTE stmt;
                                DEALLOCATE PREPARE stmt;
                            END IF;"
                    
                    log "INFO" "Suppression de la base temporaire..."
                    docker exec $CONTAINER_NAME mysql -uroot -p${MYSQL_ROOT_PASSWORD} \
                        -e "DROP DATABASE \`$TARGET_DB\`;"
                    
                    log "INFO" "Base '$ORIGINAL_TARGET_DB' remplacée avec succès"
                else
                    log "INFO" "La base temporaire '$TARGET_DB' a été conservée"
                fi
            fi
        else
            log "INFO" "Restauration complète terminée"
        fi
    else
        log "ERROR" "Échec de la restauration (code: $restore_status)"
    fi
    
    return $restore_status
}

# Nettoyage final
cleanup() {
    log "INFO" "Nettoyage des fichiers temporaires..."
    rm -rf "$TMP_DIR"
}

# Fonction principale
main() {
    echo "====== SCRIPT AMÉLIORÉ DE RESTAURATION MYSQL ======"
    log "INFO" "Démarrage du script de restauration"
    
    parse_args "$@"
    
    # Si --interactive est spécifié, sélectionner un fichier
    if $INTERACTIVE; then
        select_backup_file
    fi
    
    # Vérifier qu'un fichier a été spécifié
    if [ -z "$BACKUP_FILE" ] && ! $INTERACTIVE; then
        log "ERROR" "Aucun fichier de sauvegarde spécifié"
        show_help
    fi
    
    check_dependencies
    check_disk_space
    prepare_backup_file
    analyze_backup
    
    # Si --preview est spécifié, afficher l'aperçu et quitter
    if $PREVIEW; then
        preview_backup
        cleanup
        exit 0
    fi
    
    prepare_target_database
    prepare_sql_file
    
    # Confirmation avant restauration
    echo
    echo "Résumé de la restauration:"
    echo "  - Fichier source: $(basename "$BACKUP_FILE")"
    echo "  - Base(s) de données identifiée(s): $DB_NAMES"
    if [ -n "$TARGET_DB" ]; then
        echo "  - Base de données cible: $TARGET_DB"
    else
        echo "  - Mode: Restauration complète"
    fi
    
    if [ -n "$TARGET_TABLE" ]; then
        echo "  - Table ciblée: $TARGET_TABLE"
    fi
    
    if $STRUCTURE_ONLY; then
        echo "  - Mode: Structure uniquement (sans données)"
    fi
    
    if $TO_TEMP; then
        echo "  - Restauration dans une base temporaire: $TARGET_DB"
    fi
    
    if $DRY_RUN; then
        echo "  - Mode simulation: aucune modification ne sera effectuée"
    fi
    
    echo
    
    if ! $DRY_RUN; then
        read -p "Continuer avec la restauration? (o/n): " confirm
        if [[ "$confirm" != "o" && "$confirm" != "O" && "$confirm" != "oui" ]]; then
            log "INFO" "Restauration abandonnée à la demande de l'utilisateur"
            cleanup
            exit 0
        fi
    fi
    
    # Exécuter la restauration
    restore_database
    
    # Nettoyage final
    cleanup
    
    log "INFO" "Restauration terminée"
    echo "====== FIN DU SCRIPT DE RESTAURATION ======"
    echo "Log complet disponible dans: $LOG_FILE"
}

# Exécution du script
main "$@"