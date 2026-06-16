CREATE DATABASE IF NOT EXISTS opsdb;
USE opsdb;

CREATE TABLE IF NOT EXISTS bootstrap_marker (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  node_name VARCHAR(64) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO bootstrap_marker (node_name) VALUES ('mariadb-primary');
