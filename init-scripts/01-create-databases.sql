-- Création des bases de données
CREATE DATABASE IF NOT EXISTS application_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS analytics_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Attribution des privilèges
GRANT ALL PRIVILEGES ON application_db.* TO 'app_user'@'%';
GRANT SELECT, INSERT, UPDATE ON analytics_db.* TO 'app_user'@'%';

-- Création d'un utilisateur lecture seule pour les rapports
CREATE USER IF NOT EXISTS 'readonly_user'@'%' IDENTIFIED BY 'readonly_password';
GRANT SELECT ON application_db.* TO 'readonly_user'@'%';
GRANT SELECT ON analytics_db.* TO 'readonly_user'@'%';

FLUSH PRIVILEGES;