-- Utilisation de la base de données principale
USE application_db;

-- Insertion des données utilisateurs (avec des mots de passe hashés)
INSERT INTO `users` (`username`, `email`, `password_hash`, `first_name`, `last_name`, `active`)
VALUES
    ('admin', 'admin@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Admin', 'User', TRUE),
    ('jdupont', 'jean.dupont@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Jean', 'Dupont', TRUE),
    ('amoreau', 'alice.moreau@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Alice', 'Moreau', TRUE),
    ('pmartin', 'pierre.martin@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Pierre', 'Martin', TRUE),
    ('sbernard', 'sophie.bernard@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Sophie', 'Bernard', TRUE)
ON DUPLICATE KEY UPDATE
    `active` = VALUES(`active`);

-- Insertion des profils utilisateurs
INSERT INTO `user_profiles` (`user_id`, `bio`, `location`, `website`)
VALUES
    (1, 'Administrateur système', 'Paris, France', 'https://admin-portfolio.example.com'),
    (2, 'Développeur web passionné', 'Lyon, France', 'https://jean-dupont.example.com'),
    (3, 'Designer UX/UI', 'Bordeaux, France', 'https://alice-design.example.com'),
    (4, 'Ingénieur DevOps', 'Nantes, France', 'https://pierre-tech.example.com'),
    (5, 'Data scientist', 'Lille, France', 'https://sophie-data.example.com')
ON DUPLICATE KEY UPDATE
    `bio` = VALUES(`bio`),
    `location` = VALUES(`location`),
    `website` = VALUES(`website`);

-- Insertion des catégories de produits
INSERT INTO `categories` (`name`, `description`, `parent_id`)
VALUES
    ('Électronique', 'Produits électroniques et gadgets', NULL),
    ('Ordinateurs', 'Ordinateurs portables et de bureau', 1),
    ('Smartphones', 'Téléphones mobiles et accessoires', 1),
    ('Vêtements', 'Vêtements pour hommes et femmes', NULL),
    ('Hommes', 'Vêtements pour hommes', 4),
    ('Femmes', 'Vêtements pour femmes', 4)
ON DUPLICATE KEY UPDATE
    `name` = VALUES(`name`),
    `description` = VALUES(`description`);

-- Insertion des produits
INSERT INTO `products` (`category_id`, `name`, `description`, `price`, `stock_quantity`, `sku`, `active`)
VALUES
    (2, 'Ordinateur portable XPS', 'Ordinateur portable haute performance', 1299.99, 50, 'LP001', TRUE),
    (2, 'MacBook Pro', 'MacBook Pro avec puce M1', 1499.99, 30, 'LP002', TRUE),
    (3, 'iPhone 14', 'Smartphone haut de gamme', 999.99, 100, 'SP001', TRUE),
    (3, 'Samsung Galaxy S22', 'Smartphone Android premium', 899.99, 75, 'SP002', TRUE),
    (5, 'T-shirt Coton Bio', 'T-shirt en coton bio pour homme', 29.99, 200, 'TS001', TRUE),
    (5, 'Jean Slim Fit', 'Jean slim pour homme', 59.99, 120, 'JN001', TRUE),
    (6, 'Robe d\'été', 'Robe légère pour l\'été', 49.99, 80, 'DR001', TRUE),
    (6, 'Blouse en Soie', 'Blouse élégante en soie', 79.99, 60, 'BL001', TRUE)
ON DUPLICATE KEY UPDATE
    `name` = VALUES(`name`),
    `description` = VALUES(`description`),
    `price` = VALUES(`price`),
    `stock_quantity` = VALUES(`stock_quantity`),
    `active` = VALUES(`active`);

-- Insertion des commandes
INSERT INTO `orders` (`user_id`, `status`, `total_amount`, `shipping_address`, `billing_address`, `payment_method`)
VALUES
    (2, 'delivered', 1299.99, '123 Rue de Paris, 75001 Paris, France', '123 Rue de Paris, 75001 Paris, France', 'credit_card'),
    (3, 'shipped', 1079.98, '456 Avenue de Lyon, 69002 Lyon, France', '456 Avenue de Lyon, 69002 Lyon, France', 'paypal'),
    (4, 'processing', 129.97, '789 Boulevard de Bordeaux, 33000 Bordeaux, France', '789 Boulevard de Bordeaux, 33000 Bordeaux, France', 'credit_card'),
    (5, 'pending', 899.99, '101 Rue de Lille, 59000 Lille, France', '101 Rue de Lille, 59000 Lille, France', 'bank_transfer')
ON DUPLICATE KEY UPDATE
    `status` = VALUES(`status`);

-- Insertion des détails de commandes
INSERT INTO `order_items` (`order_id`, `product_id`, `quantity`, `unit_price`, `total_price`)
VALUES
    (1, 1, 1, 1299.99, 1299.99),
    (2, 3, 1, 999.99, 999.99),
    (2, 5, 2, 29.99, 59.98),
    (3, 5, 3, 29.99, 89.97),
    (3, 6, 1, 59.99, 59.99),
    (4, 4, 1, 899.99, 899.99);

-- Utilisation de la base de données d'analytique
USE analytics_db;

-- Insertion des statistiques quotidiennes
INSERT INTO `daily_stats` (`date`, `active_users`, `new_users`, `total_orders`, `total_revenue`, `avg_order_value`)
VALUES
    (DATE_SUB(CURDATE(), INTERVAL 7 DAY), 120, 15, 35, 12500.50, 357.16),
    (DATE_SUB(CURDATE(), INTERVAL 6 DAY), 135, 12, 42, 15200.75, 361.92),
    (DATE_SUB(CURDATE(), INTERVAL 5 DAY), 142, 18, 38, 13800.25, 363.16),
    (DATE_SUB(CURDATE(), INTERVAL 4 DAY), 130, 10, 31, 11200.50, 361.31),
    (DATE_SUB(CURDATE(), INTERVAL 3 DAY), 145, 22, 45, 16500.00, 366.67),
    (DATE_SUB(CURDATE(), INTERVAL 2 DAY), 150, 17, 50, 18200.25, 364.01),
    (DATE_SUB(CURDATE(), INTERVAL 1 DAY), 155, 20, 48, 17500.75, 364.60),
    (CURDATE(), 160, 15, 25, 9800.50, 392.02)
ON DUPLICATE KEY UPDATE
    `active_users` = VALUES(`active_users`),
    `new_users` = VALUES(`new_users`),
    `total_orders` = VALUES(`total_orders`),
    `total_revenue` = VALUES(`total_revenue`),
    `avg_order_value` = VALUES(`avg_order_value`);