#!/bin/bash

# Script amélioré de sauvegarde pour MySQL utilisant Docker
# Utilisation: ./backup.sh [nom_base_de_données] [options]
# Options:
#   --encrypt              Chiffrer la sauvegarde avec gpg
#   --upload               Transférer vers stockage distant
#   --retention=JOURS      Durée de conservation (défaut: 30)
#   --compress=gzip|xz     Méthode de compression (défaut: gzip)

# Charger les variables d'environnement
if [ -f .env ]; then
    source .env
fi

# Traitement des options
ENCRYPT=false
UPLOAD=false
RETENTION=30
COMPRESS="gzip"

for arg in "$@"; do
    case $arg in
        --encrypt)
            ENCRYPT=true
            shift
            ;;
        --upload)
            UPLOAD=true
            shift
            ;;
        --retention=*)
            RETENTION="${arg#*=}"
            shift
            ;;
        --compress=*)
            COMPRESS="${arg#*=}"
            shift
            ;;
    esac
done

# Configuration
CONTAINER_NAME="mysql_db"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR=${MYSQL_BACKUP_DIR:-./backup}
LOG_DIR="$BACKUP_DIR/logs"
LOG_FILE="$LOG_DIR/backup_${TIMESTAMP}.log"

# Créer les répertoires nécessaires
mkdir -p $BACKUP_DIR $LOG_DIR

# Journal avec horodatage
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Vérifier l'espace disque disponible
check_disk_space() {
    log "Vérification de l'espace disque..."
    AVAILABLE=$(df -BM --output=avail $BACKUP_DIR | tail -n1 | sed 's/M//')
    if [ $AVAILABLE -lt 1000 ]; then  # Moins de 1GB disponible
        log "AVERTISSEMENT: Espace disque faible ($AVAILABLE MB)"
        # Possible suppression des anciennes sauvegardes ici
    fi
}

# Calculer la somme de contrôle d'un fichier
calculate_checksum() {
    if command -v sha256sum &> /dev/null; then
        sha256sum "$1" > "$1.sha256"
        log "Somme de contrôle SHA256 calculée et stockée dans $1.sha256"
    else
        log "AVERTISSEMENT: sha256sum non disponible, somme de contrôle non calculée"
    fi
}

# Fonction pour le chiffrement
encrypt_backup() {
    local input_file=$1
    local output_file="$input_file.gpg"
    
    if command -v gpg &> /dev/null; then
        if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
            log "ERREUR: Variable BACKUP_ENCRYPTION_KEY non définie"
            return 1
        fi
        
        log "Chiffrement de la sauvegarde..."
        gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
            --symmetric --cipher-algo AES256 -o "$output_file" "$input_file"
        
        if [ $? -eq 0 ]; then
            rm "$input_file"  # Supprimer le fichier non chiffré
            log "Sauvegarde chiffrée avec succès: $output_file"
            return 0
        else
            log "ERREUR lors du chiffrement"
            return 1
        fi
    else
        log "ERREUR: gpg non installé, chiffrement impossible"
        return 1
    fi
}

# Fonction pour transférer vers un stockage distant
upload_backup() {
    local file=$1
    
    if [ -z "$REMOTE_STORAGE_TYPE" ]; then
        log "ERREUR: Type de stockage distant non configuré"
        return 1
    fi
    
    log "Transfert vers stockage distant ($REMOTE_STORAGE_TYPE)..."
    
    case $REMOTE_STORAGE_TYPE in
        s3)
            if command -v aws &> /dev/null; then
                aws s3 cp "$file" "s3://$S3_BUCKET/backups/$(basename $file)"
                if [ $? -eq 0 ]; then
                    log "Transfert S3 réussi: s3://$S3_BUCKET/backups/$(basename $file)"
                else
                    log "ERREUR lors du transfert S3"
                fi
            else
                log "ERREUR: AWS CLI non installé"
            fi
            ;;
        # Autres types de stockage: sftp, gcs, etc.
    esac
}

# Vérification de l'état de MySQL
check_mysql_health() {
    log "Vérification de l'état de MySQL..."
    if ! docker exec $CONTAINER_NAME mysqladmin -uroot -p${MYSQL_ROOT_PASSWORD} ping --silent; then
        log "ERREUR: MySQL ne répond pas"
        return 1
    fi
    log "MySQL fonctionne correctement"
    return 0
}

# Fonction principale de sauvegarde
perform_backup() {
    local db_name=$1
    local backup_file
    
    if [ -n "$db_name" ]; then
        backup_file="${BACKUP_DIR}/${db_name}_${TIMESTAMP}.sql"
        log "Sauvegarde de la base de données $db_name..."
        docker exec $CONTAINER_NAME mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} \
            --single-transaction --quick --lock-tables=false \
            --skip-lock-tables --set-gtid-purged=OFF \
            --routines --triggers --events \
            $db_name > $backup_file
    else
        backup_file="${BACKUP_DIR}/all_databases_${TIMESTAMP}.sql"
        log "Sauvegarde de toutes les bases de données..."
        docker exec $CONTAINER_NAME mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} \
            --single-transaction --quick --lock-tables=false \
            --skip-lock-tables --set-gtid-purged=OFF \
            --routines --triggers --events \
            --all-databases > $backup_file
    fi
    
    if [ $? -ne 0 ]; then
        log "ERREUR lors de la sauvegarde"
        return 1
    fi
    
    log "Sauvegarde brute terminée: $(du -h $backup_file | awk '{print $1}')"
    
    # Compression
    local compressed_file
    case $COMPRESS in
        gzip)
            compressed_file="$backup_file.gz"
            gzip -9 -f $backup_file
            ;;
        xz)
            compressed_file="$backup_file.xz"
            xz -9 -f $backup_file
            ;;
        *)
            log "ERREUR: Méthode de compression '$COMPRESS' non supportée"
            return 1
            ;;
    esac
    
    backup_file=$compressed_file
    log "Sauvegarde compressée: $(du -h $backup_file | awk '{print $1}')"
    
    # Calcul de la somme de contrôle
    calculate_checksum $backup_file
    
    # Chiffrement si demandé
    if $ENCRYPT; then
        encrypt_backup $backup_file
        if [ $? -eq 0 ]; then
            backup_file="$backup_file.gpg"
        fi
    fi
    
    # Transfert vers stockage distant si demandé
    if $UPLOAD; then
        upload_backup $backup_file
    fi
    
    log "Sauvegarde terminée avec succès: $backup_file"
    return 0
}

# Nettoyage des anciennes sauvegardes
cleanup_old_backups() {
    log "Nettoyage des sauvegardes de plus de $RETENTION jours..."
    find $BACKUP_DIR -type f -name "*.sql.gz" -o -name "*.sql.xz" -o -name "*.sql.gz.gpg" -o -name "*.sql.xz.gpg" -mtime +$RETENTION -delete
    log "Nettoyage terminé"
}

# Fonction principale
main() {
    log "Démarrage du processus de sauvegarde..."
    
    # Vérifications préalables
    check_disk_space
    if ! check_mysql_health; then
        log "ERREUR CRITIQUE: MySQL non disponible. Abandon."
        exit 1
    fi
    
    # Effectuer la sauvegarde
    if perform_backup "$1"; then
        # Nettoyage des anciennes sauvegardes
        cleanup_old_backups
        
        # Résumé
        log "RÉSUMÉ DE LA SAUVEGARDE:"
        log "  - Bases sauvegardées: ${1:-'Toutes'}"
        log "  - Taille totale du répertoire de sauvegarde: $(du -sh $BACKUP_DIR | awk '{print $1}')"
        log "  - Nombre total de sauvegardes: $(find $BACKUP_DIR -type f -name "*.sql.*" | wc -l)"
        exit 0
    else
        log "ERREUR: Échec de la sauvegarde"
        # Envoi d'une notification d'échec
        exit 1
    fi
}

main "$1"