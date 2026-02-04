-- Create Keila user and database on the shared Postgres instance.
-- Runs once when the Postgres data directory is first initialized.
CREATE USER keila WITH PASSWORD 'keila';
CREATE DATABASE keila OWNER keila;
