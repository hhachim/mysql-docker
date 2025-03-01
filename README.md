# Projet MySQL Docker Professionnel

Un environnement Docker complet pour MySQL, facile à déployer en local ou sur une VM Linux, avec création automatique de bases de données et chargement initial de données.

## Fonctionnalités

- ✅ Configuration MySQL optimisée et sécurisée
- ✅ Création automatique de bases de données et tables
- ✅ Chargement automatique de données de test
- ✅ Interface d'administration via Adminer
- ✅ Scripts de sauvegarde et restauration
- ✅ Script de déploiement automatisé pour VMs Linux
- ✅ Volumes persistants pour les données
- ✅ Environnement de développement local prêt à l'emploi

## Prérequis

- Docker
- Docker Compose

## Structure du projet

```
docker-mysql-project/
├── docker-compose.yml      # Configuration des services
├── Dockerfile              # Personnalisation de l'image MySQL
├── .env                    # Variables d'environnement
├── mysql-config/
│   └── my.cnf              # Configuration MySQL
├── init-scripts/           # Scripts d'initialisation
│   ├── 01-create-databases.sql
│   ├── 02-create-tables.sql
│   └── 03-insert-data.sql
├── scripts/
│   ├── backup.sh           # Script de sauvegarde
│   ├── restore.sh          # Script de restauration
│   └── deploy.sh           # Script de déploiement sur VM
├── data/                   # Stockage persistant des données
│   └── .gitkeep
└── backup/                 # Dossier des sauvegardes
    └── .gitkeep
```

## Installation locale

1. Clonez ce dépôt:
   ```bash
   git clone https://github.com/votre-username/docker-mysql-project.git
   cd docker-mysql-project
   ```

2. Personnalisez le fichier `.env` avec vos paramètres:
   ```bash
   cp .env.example .env
   nano .env
   ```

3. Démarrez les services:
   ```bash
   docker-compose up -d
   ```

4. Vérifiez que tout fonctionne:
   ```bash
   docker-compose ps
   ```

## Déploiement sur VM Linux

1. Copiez le projet sur votre VM:
   ```bash
   scp -r docker-mysql-project user@server-ip:~/
   ```

2. Connectez-vous à votre VM:
   ```bash
   ssh user@server-ip
   ```

3. Exécutez le script de déploiement:
   ```bash
   cd docker-mysql-project
   chmod +x scripts/deploy.sh
   sudo ./scripts/deploy.sh
   ```

## Administration

### Interface Web (Adminer)

Accédez à Adminer via http://localhost:8080 (ou http://ip-de-votre-vm:8080) et connectez-vous avec:

- Système: MySQL
- Serveur: mysql (ou l'adresse IP du conteneur, voir ci-dessous)
- Port: le port défini dans .env (3306 par défaut)
- Utilisateur: app_user (ou root)
- Mot de passe: (celui défini dans .env)
- Base de données: application_db (ou autre)

Si vous avez modifié le port MySQL par défaut (3306) dans le fichier .env, exécutez le script d'aide :
```bash
chmod +x scripts/adminer-fix.sh
./scripts/adminer-fix.sh
```
Ce script vous fournira les informations de connexion correctes pour Adminer.

### Ligne de commande

```bash
# Connexion au conteneur MySQL
docker exec -it mysql_db bash

# Connexion à MySQL depuis l'hôte
mysql -h127.0.0.1 -P3306 -uapp_user -p application_db
```

## Sauvegarde et restauration

Les scripts utilisent le MySQL dans le conteneur Docker, aucune installation locale de MySQL n'est nécessaire.

### Créer une sauvegarde

```bash
# S'assurer que les scripts sont exécutables
chmod +x scripts/backup.sh scripts/restore.sh

# Sauvegarde complète
./scripts/backup.sh

# Sauvegarde d'une base spécifique
./scripts/backup.sh application_db
```

### Restaurer une sauvegarde

```bash
# Restauration complète
./scripts/restore.sh backup/all_databases_20250301_120000.sql.gz

# Restauration dans une base spécifique
./scripts/restore.sh backup/application_db_20250301_120000.sql.gz application_db
```

Les scripts vérifient automatiquement que le conteneur MySQL est en cours d'exécution et utilisent la commande `docker exec` pour interagir avec MySQL à l'intérieur du conteneur.

## Schéma de base de données

Le projet crée deux bases de données:

1. **application_db** - Base principale de l'application
   - Tables: users, user_profiles, categories, products, orders, order_items

2. **analytics_db** - Base pour l'analyse et les statistiques
   - Tables: activity_logs, daily_stats

## Personnalisation

### Modifier la configuration MySQL

Éditez le fichier `mysql-config/my.cnf` pour ajuster les paramètres MySQL.

### Ajouter de nouvelles bases de données ou tables

Ajoutez ou modifiez les scripts dans le dossier `init-scripts/`.

### Changer la version de MySQL

Modifiez le `Dockerfile` pour utiliser une version différente de MySQL.

## Sécurité

Ce projet est configuré avec des pratiques de sécurité de base, mais pour un environnement de production:

1. Changez tous les mots de passe par défaut
2. Limitez l'accès réseau aux ports MySQL
3. Configurez TLS/SSL pour les connexions
4. Mettez en place un système de sauvegarde automatisé
5. Utilisez des secrets Docker pour les informations sensibles

## Dépannage

### Les services ne démarrent pas

```bash
docker-compose logs mysql
```

### Problèmes de permissions

```bash
# Assurez-vous que les répertoires ont les bonnes permissions
chmod -R 777 data backup
```

### Réinitialisation complète

```bash
# Arrêter et supprimer les conteneurs, volumes et images
docker-compose down -v
rm -rf data/*
```

## Licence

Ce projet est sous licence MIT.

## Contribution

Les contributions sont les bienvenues ! N'hésitez pas à soumettre des pull requests.