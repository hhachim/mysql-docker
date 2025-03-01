FROM mysql:8.0

# Ajout d'utilitaires pour la maintenance
# MySQL utilise Debian, donc on vérifie d'abord le gestionnaire de paquets disponible
RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && apt-get install -y \
        nano \
        iputils-ping \
        procps \
        && rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
        apk update && apk add --no-cache \
        nano \
        iputils-ping \
        procps; \
    fi

# Ajout d'un script pour les sauvegardes
COPY scripts/backup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh

# Copie de la configuration personnalisée
COPY mysql-config/my.cnf /etc/mysql/conf.d/

# Les scripts d'initialisation sont copiés via docker-compose
# dans /docker-entrypoint-initdb.d/

# Configuration du fuseau horaire (ajustez selon vos besoins)
ENV TZ=Europe/Paris

# Exposition du port MySQL
EXPOSE 3306

# Définition du volume pour les données MySQL
VOLUME /var/lib/mysql

# Point d'entrée par défaut fourni par l'image MySQL
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["mysqld"]