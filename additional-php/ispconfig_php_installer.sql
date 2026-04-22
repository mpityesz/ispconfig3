-- SQL script to add PHP versions to ISPConfig database.
-- Set the server_id variable to the desired server ID (default 1).
SET @server_id = 1;

-- Insert PHP versions into the server_php table. Using INSERT IGNORE to avoid duplicates.
INSERT IGNORE INTO server_php (server_id, client_id, name, php_fastcgi_binary, php_fastcgi_ini_dir, php_fpm_init_script, php_fpm_ini_dir, php_fpm_pool_dir) VALUES
(@server_id, 0, 'PHP 5.6 FPM', '/usr/bin/php-cgi5.6', '/etc/php/5.6/cgi/php.ini', 'php5.6-fpm', '/etc/php/5.6/fpm/php.ini', '/etc/php/5.6/fpm/pool.d'),
(@server_id, 0, 'PHP 7.0 FPM', '/usr/bin/php-cgi7.0', '/etc/php/7.0/cgi/php.ini', 'php7.0-fpm', '/etc/php/7.0/fpm/php.ini', '/etc/php/7.0/fpm/pool.d'),
(@server_id, 0, 'PHP 7.1 FPM', '/usr/bin/php-cgi7.1', '/etc/php/7.1/cgi/php.ini', 'php7.1-fpm', '/etc/php/7.1/fpm/php.ini', '/etc/php/7.1/fpm/pool.d'),
(@server_id, 0, 'PHP 7.2 FPM', '/usr/bin/php-cgi7.2', '/etc/php/7.2/cgi/php.ini', 'php7.2-fpm', '/etc/php/7.2/fpm/php.ini', '/etc/php/7.2/fpm/pool.d'),
(@server_id, 0, 'PHP 7.3 FPM', '/usr/bin/php-cgi7.3', '/etc/php/7.3/cgi/php.ini', 'php7.3-fpm', '/etc/php/7.3/fpm/php.ini', '/etc/php/7.3/fpm/pool.d'),
(@server_id, 0, 'PHP 7.4 FPM', '/usr/bin/php-cgi7.4', '/etc/php/7.4/cgi/php.ini', 'php7.4-fpm', '/etc/php/7.4/fpm/php.ini', '/etc/php/7.4/fpm/pool.d'),
(@server_id, 0, 'PHP 8.0 FPM', '/usr/bin/php-cgi8.0', '/etc/php/8.0/cgi/php.ini', 'php8.0-fpm', '/etc/php/8.0/fpm/php.ini', '/etc/php/8.0/fpm/pool.d'),
(@server_id, 0, 'PHP 8.1 FPM', '/usr/bin/php-cgi8.1', '/etc/php/8.1/cgi/php.ini', 'php8.1-fpm', '/etc/php/8.1/fpm/php.ini', '/etc/php/8.1/fpm/pool.d'),
(@server_id, 0, 'PHP 8.2 FPM', '/usr/bin/php-cgi8.2', '/etc/php/8.2/cgi/php.ini', 'php8.2-fpm', '/etc/php/8.2/fpm/php.ini', '/etc/php/8.2/fpm/pool.d'),
(@server_id, 0, 'PHP 8.3 FPM', '/usr/bin/php-cgi8.3', '/etc/php/8.3/cgi/php.ini', 'php8.3-fpm', '/etc/php/8.3/fpm/php.ini', '/etc/php/8.3/fpm/pool.d'),
(@server_id, 0, 'PHP 8.4 FPM', '/usr/bin/php-cgi8.4', '/etc/php/8.4/cgi/php.ini', 'php8.4-fpm', '/etc/php/8.4/fpm/php.ini', '/etc/php/8.4/fpm/pool.d');

-- Select query to verify inserted records.
SELECT * FROM server_php WHERE server_id = @server_id;

-- Note: After importing, remember to manually set PHP-FPM socket directory to /run/php/ in ISPConfig web interface.
