-- ==========================
-- 1. CENTRAL DATABASE
-- ==========================
CREATE DATABASE pos_central;
\c pos_central;

CREATE EXTENSION IF NOT EXISTS dblink;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- --------------------------
-- Security / Roles
-- --------------------------
-- Full admin
CREATE ROLE central_admin LOGIN PASSWORD 'admin123';
GRANT ALL PRIVILEGES ON DATABASE pos_central TO central_admin;

-- Restricted dblink user
CREATE ROLE dblink_user LOGIN PASSWORD 'dblink123';
GRANT CONNECT ON DATABASE pos_central, karachi_db, lahore_db TO dblink_user;

-- Allow schema/table access for dblink_user
GRANT USAGE ON SCHEMA public TO dblink_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO dblink_user;

--  Grant sequence privileges
GRANT USAGE, SELECT, UPDATE ON SEQUENCE order_mapping_id_seq TO dblink_user;

-- --------------------------
-- Tables
-- --------------------------

-- Cities
CREATE TABLE Cities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Categories
CREATE TABLE Categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Products
CREATE TABLE Products (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    category_id INT NOT NULL REFERENCES Categories(id),
    price NUMERIC(12,2) NOT NULL CHECK(price >= 0),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Stores
CREATE TABLE Stores (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(50) UNIQUE NOT NULL,
    city_id INT NOT NULL REFERENCES Cities(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Customers
CREATE TABLE Customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(150),
    city_id INT NOT NULL REFERENCES Cities(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Order Mapping
CREATE TABLE Order_Mapping (
    id SERIAL PRIMARY KEY,
    global_order_id UUID UNIQUE DEFAULT gen_random_uuid(),
    store_id INT NOT NULL REFERENCES Stores(id),
    store_order_id INT NOT NULL,
    customer_id INT,
    order_time TIMESTAMPTZ DEFAULT now()
);

-- Replication Logging
CREATE TABLE Replication_Log (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(50),
    record_id INT,
    target_db VARCHAR(50),
    status VARCHAR(20),
    message TEXT,
    log_time TIMESTAMPTZ DEFAULT now()
);

-- ==========================
-- 2. STORE DATABASES
-- ==========================
CREATE DATABASE karachi_db;
CREATE DATABASE lahore_db;

-- --------------------------
-- Tables for store DBs (same for both)
-- --------------------------
\c karachi_db

CREATE TABLE Customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(150),
    city_id INT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE Stores (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(50) UNIQUE NOT NULL,
    city_id INT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE Orders (
    id SERIAL PRIMARY KEY,
    global_order_id UUID NOT NULL,
    store_id INT NOT NULL REFERENCES Stores(id),
    customer_id INT NOT NULL REFERENCES Customers(id),
    order_date TIMESTAMPTZ DEFAULT now(),
    total_amount NUMERIC(12,2) NOT NULL,
    status VARCHAR(50) DEFAULT 'Pending',
    store_order_id INT NOT NULL,
    UNIQUE(store_id, store_order_id)
);

CREATE TABLE Order_Items (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES Orders(id),
    product_id INT NOT NULL,
    quantity INT NOT NULL CHECK(quantity > 0),
    price NUMERIC(12,2) NOT NULL
);

CREATE TABLE Payments (
    id SERIAL PRIMARY KEY,
    global_order_id UUID NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    method VARCHAR(50) CHECK(method IN ('Cash','Card','Online')),
    status VARCHAR(50) DEFAULT 'Paid'
);

CREATE TABLE Inventory (
    id SERIAL PRIMARY KEY,
    product_id INT NOT NULL,
    store_id INT NOT NULL REFERENCES Stores(id),
    quantity INT NOT NULL DEFAULT 0,
    purchase_price NUMERIC(12,2),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(product_id, store_id)
);

\c lahore_db

CREATE TABLE Customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(150),
    city_id INT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE Stores (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(50) UNIQUE NOT NULL,
    city_id INT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE Orders (
    id SERIAL PRIMARY KEY,
    global_order_id UUID NOT NULL,
    store_id INT NOT NULL REFERENCES Stores(id),
    customer_id INT NOT NULL REFERENCES Customers(id),
    order_date TIMESTAMPTZ DEFAULT now(),
    total_amount NUMERIC(12,2) NOT NULL,
    status VARCHAR(50) DEFAULT 'Pending',
    store_order_id INT NOT NULL,
    UNIQUE(store_id, store_order_id)
);

CREATE TABLE Order_Items (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES Orders(id),
    product_id INT NOT NULL,
    quantity INT NOT NULL CHECK(quantity > 0),
    price NUMERIC(12,2) NOT NULL
);

CREATE TABLE Payments (
    id SERIAL PRIMARY KEY,
    global_order_id UUID NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    method VARCHAR(50) CHECK(method IN ('Cash','Card','Online')),
    status VARCHAR(50) DEFAULT 'Paid'
);

CREATE TABLE Inventory (
    id SERIAL PRIMARY KEY,
    product_id INT NOT NULL,
    store_id INT NOT NULL REFERENCES Stores(id),
    quantity INT NOT NULL DEFAULT 0,
    purchase_price NUMERIC(12,2),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(product_id, store_id)
);

-- ==========================
-- 3. REPLICATION TRIGGERS with Logging
-- ==========================
\c pos_central

-- Customers replication
CREATE OR REPLACE FUNCTION replicate_customers() RETURNS TRIGGER AS $$
DECLARE 
    db_name TEXT;
BEGIN
    IF NEW.city_id = (SELECT id FROM Cities WHERE name='Karachi') THEN
        db_name := 'karachi_db';
    ELSE
        db_name := 'lahore_db';
    END IF;

    BEGIN
        PERFORM dblink_exec(
            'host=localhost port=5432 dbname='||db_name||' user=dblink_user password=dblink123',
            'INSERT INTO Customers (id,name,phone,email,city_id,created_at,updated_at) VALUES ('||
            NEW.id||','''||NEW.name||''','''||COALESCE(NEW.phone,'')||''','''||COALESCE(NEW.email,'')||''','||
            NEW.city_id||','''||NEW.created_at||''','''||NEW.updated_at||''') '||
            'ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, phone=EXCLUDED.phone, email=EXCLUDED.email, city_id=EXCLUDED.city_id, updated_at=EXCLUDED.updated_at'
        );
        INSERT INTO Replication_Log(table_name, record_id, target_db, status, message)
        VALUES ('Customers', NEW.id, db_name, 'Success', 'Replicated successfully');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO Replication_Log(table_name, record_id, target_db, status, message)
        VALUES ('Customers', NEW.id, db_name, 'Failed', SQLERRM);
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_customers
AFTER INSERT OR UPDATE ON Customers
FOR EACH ROW EXECUTE FUNCTION replicate_customers();

-- Stores replication
CREATE OR REPLACE FUNCTION replicate_stores() RETURNS TRIGGER AS $$
DECLARE 
    db_name TEXT;
BEGIN
    IF NEW.city_id = (SELECT id FROM Cities WHERE name='Karachi') THEN
        db_name := 'karachi_db';
    ELSE
        db_name := 'lahore_db';
    END IF;

    BEGIN
        PERFORM dblink_exec(
            'host=localhost port=5432 dbname='||db_name||' user=dblink_user password=dblink123',
            'INSERT INTO Stores (id,name,code,city_id,created_at,updated_at) VALUES ('||
            NEW.id||','''||NEW.name||''','''||NEW.code||''','||NEW.city_id||','''||NEW.created_at||''','''||NEW.updated_at||''') '||
            'ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, code=EXCLUDED.code, city_id=EXCLUDED.city_id, updated_at=EXCLUDED.updated_at'
        );
        INSERT INTO Replication_Log(table_name, record_id, target_db, status, message)
        VALUES ('Stores', NEW.id, db_name, 'Success', 'Replicated successfully');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO Replication_Log(table_name, record_id, target_db, status, message)
        VALUES ('Stores', NEW.id, db_name, 'Failed', SQLERRM);
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_stores
AFTER INSERT OR UPDATE ON Stores
FOR EACH ROW EXECUTE FUNCTION replicate_stores();

-- ==========================
-- 4. Process Order Procedure with Concurrency Control
-- ==========================
CREATE OR REPLACE FUNCTION ProcessOrder(
    p_store_id INT,
    p_customer_id INT,
    p_items JSONB,
    p_payment_method VARCHAR
) RETURNS UUID AS $$
DECLARE
    v_global_order_id UUID := gen_random_uuid();
    v_total_amount NUMERIC := 0;
    v_item JSONB;
    v_order_id INT;
    v_store_order_id INT;
BEGIN
    -- Calculate total amount
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        v_total_amount := v_total_amount + (v_item->>'quantity')::NUMERIC * (v_item->>'price')::NUMERIC;
    END LOOP;

    -- Get next store_order_id (local to this store)
    SELECT COALESCE(MAX(store_order_id),0)+1 INTO v_store_order_id FROM Orders WHERE store_id = p_store_id;

    -- Insert into Orders table (local)
    INSERT INTO Orders(global_order_id, store_id, customer_id, total_amount, status, order_date, store_order_id)
    VALUES (v_global_order_id, p_store_id, p_customer_id, v_total_amount, 'Pending', now(), v_store_order_id);

    SELECT id INTO v_order_id FROM Orders WHERE global_order_id = v_global_order_id;

    -- Insert order items and update inventory
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        -- Lock inventory row
        PERFORM 1 FROM Inventory
        WHERE product_id = (v_item->>'product_id')::INT AND store_id = p_store_id
        FOR UPDATE;

        -- Insert order item
        INSERT INTO Order_Items(order_id, product_id, quantity, price)
        VALUES (v_order_id, (v_item->>'product_id')::INT, (v_item->>'quantity')::INT, (v_item->>'price')::NUMERIC);

        -- Update inventory
        UPDATE Inventory
        SET quantity = quantity - (v_item->>'quantity')::INT,
            updated_at = now()
        WHERE product_id = (v_item->>'product_id')::INT AND store_id = p_store_id;
    END LOOP;

    -- Insert payment
    INSERT INTO Payments(global_order_id, amount, method, status)
    VALUES (v_global_order_id, v_total_amount, p_payment_method, 'Paid');

    -- Insert mapping into central database using dblink
    PERFORM dblink_exec(
        'host=localhost port=5432 dbname=pos_central user=dblink_user password=dblink123',
        'INSERT INTO Order_Mapping (store_id, store_order_id, customer_id, global_order_id, order_time) VALUES ('||
        p_store_id||','||v_store_order_id||','||p_customer_id||','''||v_global_order_id||''',now())'
    );

    RETURN v_global_order_id;
END;
$$ LANGUAGE plpgsql;

-- ==========================
-- 5. Distributed Query (Sales total)
-- ==========================
EXPLAIN ANALYZE
WITH karachi_sales AS (
    SELECT SUM(quantity*price) AS total
    FROM dblink('host=localhost port=5432 dbname=karachi_db user=dblink_user password=dblink123',
                'SELECT quantity, price FROM Order_Items') AS t(quantity INT, price NUMERIC)
),
lahore_sales AS (
    SELECT SUM(quantity*price) AS total
    FROM dblink('host=localhost port=5432 dbname=lahore_db user=dblink_user password=dblink123',
                'SELECT quantity, price FROM Order_Items') AS t(quantity INT, price NUMERIC)
)
SELECT COALESCE(k.total,0)+COALESCE(l.total,0) AS total_sales
FROM karachi_sales k, lahore_sales l;

-- ==========================
-- 6. Backup / Recovery
-- ==========================
-- Backup central DB
-- \! pg_dump -U central_admin -F c -b -v -f '/path/to/backup/pos_central.backup' pos_central

-- Restore central DB
-- \! pg_restore -U central_admin -d pos_central -v '/path/to/backup/pos_central.backup'

-- Backup store DBs
-- \! pg_dump -U central_admin -F c -b -v -f '/path/to/backup/karachi_db.backup' karachi_db
-- \! pg_dump -U central_admin -F c -b -v -f '/path/to/backup/lahore_db.backup' lahore_db

-- Restore store DBs
-- \! pg_restore -U central_admin -d karachi_db -v '/path/to/backup/karachi_db.backup'
-- \! pg_restore -U central_admin -d lahore_db -v '/path/to/backup/lahore_db.backup'

-- ==========================
-- 7. Fault Tolerance in Runtime (Replication)
-- ==========================

CREATE OR REPLACE FUNCTION retry_failed_replications() RETURNS void AS $$
DECLARE
    rec RECORD;
    _id INT;
    _name TEXT;
    _phone TEXT;
    _email TEXT;
    _city_id INT;
    _created_at TIMESTAMPTZ;
    _updated_at TIMESTAMPTZ;
    _code TEXT;
BEGIN
    FOR rec IN SELECT * FROM Replication_Log WHERE status='Failed'
    LOOP
        BEGIN
            IF rec.table_name='Customers' THEN
                SELECT id, name, phone, email, city_id, created_at, updated_at
                INTO _id, _name, _phone, _email, _city_id, _created_at, _updated_at
                FROM Customers WHERE id = rec.record_id;

                PERFORM dblink_exec(
                    'host=localhost port=5432 dbname='||rec.target_db||' user=dblink_user password=dblink123',
                    'INSERT INTO Customers (id,name,phone,email,city_id,created_at,updated_at) VALUES ('||
                    _id||','''||_name||''','''||COALESCE(_phone,'')||''','''||COALESCE(_email,'')||''','||
                    _city_id||','''||_created_at||''','''||_updated_at||''') '||
                    'ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, phone=EXCLUDED.phone, email=EXCLUDED.email, city_id=EXCLUDED.city_id, updated_at=EXCLUDED.updated_at'
                );
            ELSIF rec.table_name='Stores' THEN
                SELECT id, name, code, city_id, created_at, updated_at
                INTO _id, _name, _code, _city_id, _created_at, _updated_at
                FROM Stores WHERE id = rec.record_id;

                PERFORM dblink_exec(
                    'host=localhost port=5432 dbname='||rec.target_db||' user=dblink_user password=dblink123',
                    'INSERT INTO Stores (id,name,code,city_id,created_at,updated_at) VALUES ('||
                    _id||','''||_name||''','''||_code||''','||_city_id||','''||_created_at||''','''||_updated_at||''') '||
                    'ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, code=EXCLUDED.code, city_id=EXCLUDED.city_id, updated_at=EXCLUDED.updated_at'
                );
            END IF;

            -- Mark success
            UPDATE Replication_Log
            SET status='Success', message='Retried successfully', log_time=now()
            WHERE id=rec.id;

        EXCEPTION WHEN OTHERS THEN
            UPDATE Replication_Log
            SET message=SQLERRM, log_time=now()
            WHERE id=rec.id;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ==========================
-- 8. Examples of Usage
-- ==========================
-- Insert Cities
INSERT INTO Cities (name) VALUES ('Karachi'), ('Lahore');

-- Insert Categories
INSERT INTO Categories (name, description) VALUES 
('Beverages', 'Drinks and refreshments'),
('Snacks', 'Light snacks and fast food');

-- Insert Products
INSERT INTO Products (sku, name, category_id, price) VALUES 
('BEV001', 'Coca Cola', 1, 150.00),
('BEV002', 'Pepsi', 1, 150.00),
('SNK001', 'French Fries', 2, 100.00),
('SNK002', 'Chicken Nuggets', 2, 200.00);

-- Insert Stores
INSERT INTO Stores (name, code, city_id) VALUES
('Karachi Store', 'KHI001', (SELECT id FROM Cities WHERE name='Karachi')),
('Lahore Store', 'LHE001', (SELECT id FROM Cities WHERE name='Lahore'));

-- Insert Customers
INSERT INTO Customers (name, phone, email, city_id) VALUES
('Arham Sharif', '03216549870', 'sarham927@gmail.com', (SELECT id FROM Cities WHERE name='Karachi')),
('Bisma Imran', '03217894560', 'bisma@gmail.com', (SELECT id FROM Cities WHERE name='Karachi')),
('Subhan Ali', '03221456987', 'subhan@gmail.com', (SELECT id FROM Cities WHERE name='Lahore')),
('Sir Taha', '03312564789', 'taha@gmail.com', (SELECT id FROM Cities WHERE name='Lahore'));

-- Insert Inventory
INSERT INTO Inventory (product_id, store_id, quantity, purchase_price) VALUES
(1, (SELECT id FROM Stores WHERE code='KHI001'), 100, 150.00),
(3, (SELECT id FROM Stores WHERE code='KHI001'), 50, 100.00);

-- Process an Order
SELECT ProcessOrder(
    (SELECT id FROM Stores WHERE code='KHI001'),
    (SELECT id FROM Customers WHERE name='Arham Sharif'),
    '[{"product_id":1,"quantity":2,"price":150.00},{"product_id":3,"quantity":1,"price":100.00}]'::JSONB,
    'Cash'
);

-- ==========================
-- END SCRIPT
-- ==========================