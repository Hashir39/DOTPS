-- ==================================================
-- DATABASE: pos_ddb (Distributed OmniCommerce Transaction Processing System)
-- ==================================================

-- Create database
CREATE DATABASE pos_ddb;
\c pos_ddb;

-- ==================================================
-- 0. Extensions
-- ==================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid, password hashes

-- pg_stat_statements is optional monitoring. Do not create it here:
-- it errors unless shared_preload_libraries already loads it.
-- After a restart with that setting:
--   CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- ==================================================
-- 1. Schemas
-- ==================================================
CREATE SCHEMA IF NOT EXISTS central;
CREATE SCHEMA IF NOT EXISTS karachi;
CREATE SCHEMA IF NOT EXISTS lahore;

-- ==================================================
-- 2. CENTRAL TABLES
-- ==================================================
SET search_path = central;

-- Cities
CREATE TABLE IF NOT EXISTS Cities (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  name VARCHAR(100) UNIQUE NOT NULL
);

-- Stores
CREATE TABLE IF NOT EXISTS Stores (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  city_id INT NOT NULL REFERENCES central.Cities(id),
  name VARCHAR(100) NOT NULL,
  code VARCHAR(50) UNIQUE NOT NULL
);

-- Categories
CREATE TABLE IF NOT EXISTS Categories (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  name VARCHAR(100) UNIQUE NOT NULL,
  description TEXT
);

-- Roles
CREATE TABLE IF NOT EXISTS Roles (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  role_name VARCHAR(50) UNIQUE NOT NULL,
  description TEXT
);

-- Users
CREATE TABLE IF NOT EXISTS Users (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  username VARCHAR(150) UNIQUE NOT NULL,
  email VARCHAR(150) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  full_name VARCHAR(100),
  role_id INT REFERENCES central.Roles(id),
  store_id INT REFERENCES central.Stores(id)
);

-- Products
CREATE TABLE IF NOT EXISTS Products (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  sku VARCHAR(100) UNIQUE NOT NULL,
  name VARCHAR(150) NOT NULL,
  category_id INT REFERENCES central.Categories(id),
  price NUMERIC(12,2) NOT NULL CHECK (price >= 0)
);

-- Suppliers
CREATE TABLE IF NOT EXISTS Suppliers (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  name VARCHAR(150) NOT NULL,
  contact_info TEXT
);

-- Inventory
CREATE TABLE IF NOT EXISTS Inventory (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  product_id INT NOT NULL REFERENCES central.Products(id),
  store_id INT NOT NULL REFERENCES central.Stores(id),
  quantity INT NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  purchase_price NUMERIC(12,2),
  UNIQUE(product_id, store_id)
);

-- Customers
CREATE TABLE IF NOT EXISTS Customers (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  city_id INT NOT NULL REFERENCES central.Cities(id),
  name VARCHAR(150) NOT NULL,
  phone VARCHAR(20),
  email VARCHAR(150)
);

-- Order_Mapping
CREATE TABLE IF NOT EXISTS Order_Mapping (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  global_order_id UUID UNIQUE DEFAULT gen_random_uuid(),
  store_id INT NOT NULL REFERENCES central.Stores(id),
  store_order_id INT NOT NULL,
  customer_id INT REFERENCES central.Customers(id),
  order_time TIMESTAMPTZ DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_order_mapping_store_order
  ON central.Order_Mapping(store_id, store_order_id);

-- Orders
CREATE TABLE IF NOT EXISTS Orders (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  global_order_id UUID NOT NULL REFERENCES central.Order_Mapping(global_order_id),
  store_id INT NOT NULL REFERENCES central.Stores(id),
  customer_id INT REFERENCES central.Customers(id),
  order_date TIMESTAMPTZ DEFAULT now(),
  total_amount NUMERIC(12,2) NOT NULL,
  status VARCHAR(50) DEFAULT 'Pending',
  tracking_code VARCHAR(50) UNIQUE DEFAULT ('TRK-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(gen_random_uuid()::text),1,6))
);

-- Order_Items
CREATE TABLE IF NOT EXISTS Order_Items (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  order_id INT NOT NULL REFERENCES central.Orders(id),
  product_id INT NOT NULL REFERENCES central.Products(id),
  quantity INT NOT NULL CHECK (quantity > 0),
  price NUMERIC(12,2) NOT NULL
);

-- Payments
CREATE TABLE IF NOT EXISTS Payments (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  updated_by INT,
  global_order_id UUID NOT NULL REFERENCES central.Order_Mapping(global_order_id),
  amount NUMERIC(12,2) NOT NULL,
  method VARCHAR(50) CHECK (method IN ('Cash','Card','Online')),
  status VARCHAR(50) DEFAULT 'Paid'
);

-- Audit_Logs
CREATE TABLE IF NOT EXISTS Audit_Logs (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by INT,
  table_name TEXT NOT NULL,
  action TEXT NOT NULL,
  payload JSONB
);

-- ==================================================
-- 3. NODES TABLES (Karachi & Lahore)
-- ==================================================
DO $$
DECLARE
  node_schema TEXT;
  table_name TEXT;
  con RECORD;
BEGIN
  FOREACH node_schema IN ARRAY ARRAY['karachi', 'lahore'] LOOP
    FOREACH table_name IN ARRAY ARRAY[
      'stores', 'categories', 'roles', 'products', 'suppliers',
      'customers', 'orders', 'order_items', 'payments', 'inventory'
    ] LOOP
      IF to_regclass(format('%I.%I', node_schema, table_name)) IS NULL THEN
        -- INCLUDING INDEXES copies primary keys and unique keys.
        -- Foreign keys are never copied by LIKE.
        EXECUTE format(
          'CREATE TABLE %I.%I (LIKE central.%I INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES)',
          node_schema, table_name, table_name
        );
      ELSE
        -- Older scripts created only a plain unique index on id.
        -- Drop it before adding the real primary key, or ON CONFLICT (id)
        -- becomes ambiguous.
        EXECUTE format(
          'DROP INDEX IF EXISTS %I.%I',
          node_schema,
          node_schema || '_' || table_name || '_id_uidx'
        );

        FOR con IN
          SELECT pg_get_constraintdef(c.oid) AS def
          FROM pg_constraint c
          JOIN pg_class rel ON rel.oid = c.conrelid
          JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
          WHERE nsp.nspname = 'central'
            AND rel.relname = table_name
            AND c.contype IN ('p', 'u')
        LOOP
          IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint existing
            JOIN pg_class rel ON rel.oid = existing.conrelid
            JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
            WHERE nsp.nspname = node_schema
              AND rel.relname = table_name
              AND pg_get_constraintdef(existing.oid) = con.def
          ) THEN
            EXECUTE format(
              'ALTER TABLE %I.%I ADD %s',
              node_schema, table_name, con.def
            );
          END IF;
        END LOOP;
      END IF;
    END LOOP;
  END LOOP;
END;
$$;

INSERT INTO karachi.Categories SELECT * FROM central.Categories ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Categories SELECT * FROM central.Categories ON CONFLICT (id) DO NOTHING;
INSERT INTO karachi.Roles SELECT * FROM central.Roles ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Roles SELECT * FROM central.Roles ON CONFLICT (id) DO NOTHING;
INSERT INTO karachi.Products SELECT * FROM central.Products ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Products SELECT * FROM central.Products ON CONFLICT (id) DO NOTHING;
INSERT INTO karachi.Suppliers SELECT * FROM central.Suppliers ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Suppliers SELECT * FROM central.Suppliers ON CONFLICT (id) DO NOTHING;

INSERT INTO karachi.Stores SELECT * FROM central.Stores
WHERE city_id = (SELECT id FROM central.Cities WHERE name = 'Karachi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Stores SELECT * FROM central.Stores
WHERE city_id = (SELECT id FROM central.Cities WHERE name = 'Lahore')
ON CONFLICT (id) DO NOTHING;
INSERT INTO karachi.Customers SELECT * FROM central.Customers
WHERE city_id = (SELECT id FROM central.Cities WHERE name = 'Karachi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Customers SELECT * FROM central.Customers
WHERE city_id = (SELECT id FROM central.Cities WHERE name = 'Lahore')
ON CONFLICT (id) DO NOTHING;

INSERT INTO karachi.Orders SELECT o.* FROM central.Orders o
JOIN central.Stores s ON s.id = o.store_id
WHERE s.city_id = (SELECT id FROM central.Cities WHERE name = 'Karachi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Orders SELECT o.* FROM central.Orders o
JOIN central.Stores s ON s.id = o.store_id
WHERE s.city_id = (SELECT id FROM central.Cities WHERE name = 'Lahore')
ON CONFLICT (id) DO NOTHING;
INSERT INTO karachi.Order_Items SELECT oi.* FROM central.Order_Items oi
JOIN central.Orders o ON o.id = oi.order_id
JOIN central.Stores s ON s.id = o.store_id
WHERE s.city_id = (SELECT id FROM central.Cities WHERE name = 'Karachi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Order_Items SELECT oi.* FROM central.Order_Items oi
JOIN central.Orders o ON o.id = oi.order_id
JOIN central.Stores s ON s.id = o.store_id
WHERE s.city_id = (SELECT id FROM central.Cities WHERE name = 'Lahore')
ON CONFLICT (id) DO NOTHING;
INSERT INTO karachi.Payments SELECT p.* FROM central.Payments p
JOIN central.Order_Mapping om ON om.global_order_id = p.global_order_id
JOIN central.Stores s ON s.id = om.store_id
WHERE s.city_id = (SELECT id FROM central.Cities WHERE name = 'Karachi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Payments SELECT p.* FROM central.Payments p
JOIN central.Order_Mapping om ON om.global_order_id = p.global_order_id
JOIN central.Stores s ON s.id = om.store_id
WHERE s.city_id = (SELECT id FROM central.Cities WHERE name = 'Lahore')
ON CONFLICT (id) DO NOTHING;
INSERT INTO karachi.Inventory SELECT i.* FROM central.Inventory i
JOIN central.Stores s ON s.id = i.store_id
WHERE s.city_id = (SELECT id FROM central.Cities WHERE name = 'Karachi')
ON CONFLICT (id) DO NOTHING;
INSERT INTO lahore.Inventory SELECT i.* FROM central.Inventory i
JOIN central.Stores s ON s.id = i.store_id
WHERE s.city_id = (SELECT id FROM central.Cities WHERE name = 'Lahore')
ON CONFLICT (id) DO NOTHING;

-- ==================================================
-- 4. FULL REPLICATION TRIGGERS (ALL TABLES)
-- ==================================================

CREATE OR REPLACE FUNCTION central.remove_regional_copies(p_table_name TEXT, p_id INT)
RETURNS VOID AS $$
DECLARE
  node_schema TEXT;
BEGIN
  IF p_table_name NOT IN (
    'stores', 'categories', 'roles', 'products', 'suppliers',
    'customers', 'orders', 'order_items', 'payments', 'inventory'
  ) THEN
    RAISE EXCEPTION 'Unsupported regional table: %', p_table_name;
  END IF;

  FOREACH node_schema IN ARRAY ARRAY['karachi', 'lahore'] LOOP
    EXECUTE format('DELETE FROM %I.%I WHERE id = $1', node_schema, p_table_name)
      USING p_id;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog;
REVOKE ALL ON FUNCTION central.remove_regional_copies(TEXT, INT) FROM PUBLIC;

-- Customers
CREATE OR REPLACE FUNCTION replicate_customers() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
    END IF;

    IF NEW.city_id = (SELECT id FROM central.Cities WHERE name='Karachi') THEN
        INSERT INTO karachi.Customers VALUES (NEW.*)
        ON CONFLICT (id) DO UPDATE 
        SET name = EXCLUDED.name,
            phone = EXCLUDED.phone,
            email = EXCLUDED.email,
            updated_at = EXCLUDED.updated_at,
            updated_by = EXCLUDED.updated_by;
   ELSIF NEW.city_id = (SELECT id FROM central.Cities WHERE name='Lahore') THEN
    INSERT INTO lahore.Customers VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE 
    SET name = EXCLUDED.name,
        phone = EXCLUDED.phone,
        email = EXCLUDED.email,
        updated_at = EXCLUDED.updated_at,
        updated_by = EXCLUDED.updated_by;
  END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_customers_insert
AFTER INSERT OR UPDATE ON central.Customers
FOR EACH ROW EXECUTE FUNCTION replicate_customers();

-- Stores
CREATE OR REPLACE FUNCTION replicate_store() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  END IF;

  IF NEW.city_id = (SELECT id FROM central.Cities WHERE name='Karachi') THEN
    INSERT INTO karachi.Stores VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, code=EXCLUDED.code, city_id=EXCLUDED.city_id, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  ELSIF NEW.city_id = (SELECT id FROM central.Cities WHERE name='Lahore') THEN
    INSERT INTO lahore.Stores VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, code=EXCLUDED.code, city_id=EXCLUDED.city_id, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_store_insert
AFTER INSERT OR UPDATE ON central.Stores
FOR EACH ROW EXECUTE FUNCTION replicate_store();

-- Products
CREATE OR REPLACE FUNCTION replicate_product() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  END IF;

  INSERT INTO karachi.Products VALUES (NEW.*)
  ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, price=EXCLUDED.price, category_id=EXCLUDED.category_id, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  
  INSERT INTO lahore.Products VALUES (NEW.*)
  ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, price=EXCLUDED.price, category_id=EXCLUDED.category_id, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_product_insert
AFTER INSERT OR UPDATE ON central.Products
FOR EACH ROW EXECUTE FUNCTION replicate_product();

-- Categories
CREATE OR REPLACE FUNCTION replicate_category() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  END IF;

  INSERT INTO karachi.Categories VALUES (NEW.*)
  ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;

  INSERT INTO lahore.Categories VALUES (NEW.*)
  ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_category_insert
AFTER INSERT OR UPDATE ON central.Categories
FOR EACH ROW EXECUTE FUNCTION replicate_category();

-- Roles
CREATE OR REPLACE FUNCTION replicate_role() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  END IF;

  INSERT INTO karachi.Roles VALUES (NEW.*)
  ON CONFLICT (id) DO UPDATE SET role_name=EXCLUDED.role_name, description=EXCLUDED.description, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;

  INSERT INTO lahore.Roles VALUES (NEW.*)
  ON CONFLICT (id) DO UPDATE SET role_name=EXCLUDED.role_name, description=EXCLUDED.description, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_role_insert
AFTER INSERT OR UPDATE ON central.Roles
FOR EACH ROW EXECUTE FUNCTION replicate_role();

-- Suppliers
CREATE OR REPLACE FUNCTION replicate_supplier() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  END IF;

  INSERT INTO karachi.Suppliers VALUES (NEW.*)
  ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, contact_info=EXCLUDED.contact_info, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;

  INSERT INTO lahore.Suppliers VALUES (NEW.*)
  ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, contact_info=EXCLUDED.contact_info, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_supplier_insert
AFTER INSERT OR UPDATE ON central.Suppliers
FOR EACH ROW EXECUTE FUNCTION replicate_supplier();

-- Orders
CREATE OR REPLACE FUNCTION replicate_orders() RETURNS TRIGGER AS $$
DECLARE store_city_id INT;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  END IF;

  SELECT city_id INTO store_city_id FROM central.Stores WHERE id = NEW.store_id;

  IF store_city_id = (SELECT id FROM central.Cities WHERE name='Karachi') THEN
    INSERT INTO karachi.Orders VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at, total_amount=EXCLUDED.total_amount;
  ELSIF store_city_id = (SELECT id FROM central.Cities WHERE name='Lahore') THEN
    INSERT INTO lahore.Orders VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at, total_amount=EXCLUDED.total_amount;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_insert
AFTER INSERT OR UPDATE ON central.Orders
FOR EACH ROW EXECUTE FUNCTION replicate_orders();

-- Order_Items
CREATE OR REPLACE FUNCTION replicate_order_items() RETURNS TRIGGER AS $$
DECLARE store_city_id INT;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  END IF;

  SELECT city_id INTO store_city_id 
  FROM central.Stores 
  WHERE id = (SELECT store_id FROM central.Orders WHERE id=NEW.order_id);

  IF store_city_id = (SELECT id FROM central.Cities WHERE name='Karachi') THEN
    INSERT INTO karachi.Order_Items VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET quantity=EXCLUDED.quantity, price=EXCLUDED.price, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  ELSIF store_city_id = (SELECT id FROM central.Cities WHERE name='Lahore') THEN
    INSERT INTO lahore.Order_Items VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET quantity=EXCLUDED.quantity, price=EXCLUDED.price, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_items_insert
AFTER INSERT OR UPDATE ON central.Order_Items
FOR EACH ROW EXECUTE FUNCTION replicate_order_items();

-- Payments
CREATE OR REPLACE FUNCTION replicate_payments() RETURNS TRIGGER AS $$
DECLARE store_city_id INT;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  END IF;

  SELECT city_id INTO store_city_id 
  FROM central.Stores 
  WHERE id = (SELECT store_id FROM central.Order_Mapping WHERE global_order_id=NEW.global_order_id);

  IF store_city_id = (SELECT id FROM central.Cities WHERE name='Karachi') THEN
    INSERT INTO karachi.Payments VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET amount=EXCLUDED.amount, status=EXCLUDED.status, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  ELSIF store_city_id = (SELECT id FROM central.Cities WHERE name='Lahore') THEN
    INSERT INTO lahore.Payments VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET amount=EXCLUDED.amount, status=EXCLUDED.status, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payments_insert
AFTER INSERT OR UPDATE ON central.Payments
FOR EACH ROW EXECUTE FUNCTION replicate_payments();

-- Inventory
CREATE OR REPLACE FUNCTION replicate_inventory() RETURNS TRIGGER AS $$
DECLARE store_city_id INT;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  END IF;

  SELECT city_id INTO store_city_id FROM central.Stores WHERE id = NEW.store_id;

  IF store_city_id = (SELECT id FROM central.Cities WHERE name='Karachi') THEN
    INSERT INTO karachi.Inventory VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET quantity=EXCLUDED.quantity, purchase_price=EXCLUDED.purchase_price, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  ELSIF store_city_id = (SELECT id FROM central.Cities WHERE name='Lahore') THEN
    INSERT INTO lahore.Inventory VALUES (NEW.*)
    ON CONFLICT (id) DO UPDATE SET quantity=EXCLUDED.quantity, purchase_price=EXCLUDED.purchase_price, updated_by=EXCLUDED.updated_by, updated_at=EXCLUDED.updated_at;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_inventory_insert
AFTER INSERT OR UPDATE ON central.Inventory
FOR EACH ROW EXECUTE FUNCTION replicate_inventory();

-- Audit Logs
CREATE OR REPLACE FUNCTION replicate_audit() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    INSERT INTO central.Audit_Logs(table_name, action, payload, created_by)
    VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), OLD.created_by);
    RETURN OLD;
  END IF;

  INSERT INTO central.Audit_Logs(table_name, action, payload, created_by)
  VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(NEW), NEW.created_by);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_users
AFTER INSERT OR UPDATE OR DELETE ON central.Users
FOR EACH ROW EXECUTE FUNCTION replicate_audit();

CREATE OR REPLACE FUNCTION replicate_regional_delete() RETURNS TRIGGER AS $$
BEGIN
  PERFORM central.remove_regional_copies(TG_TABLE_NAME, OLD.id);
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog;

CREATE TRIGGER trg_customers_delete AFTER DELETE ON central.Customers
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();
CREATE TRIGGER trg_stores_delete AFTER DELETE ON central.Stores
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();
CREATE TRIGGER trg_products_delete AFTER DELETE ON central.Products
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();
CREATE TRIGGER trg_categories_delete AFTER DELETE ON central.Categories
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();
CREATE TRIGGER trg_roles_delete AFTER DELETE ON central.Roles
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();
CREATE TRIGGER trg_suppliers_delete AFTER DELETE ON central.Suppliers
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();
CREATE TRIGGER trg_orders_delete AFTER DELETE ON central.Orders
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();
CREATE TRIGGER trg_order_items_delete AFTER DELETE ON central.Order_Items
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();
CREATE TRIGGER trg_payments_delete AFTER DELETE ON central.Payments
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();
CREATE TRIGGER trg_inventory_delete AFTER DELETE ON central.Inventory
FOR EACH ROW EXECUTE FUNCTION replicate_regional_delete();

ALTER FUNCTION central.replicate_customers() SECURITY DEFINER;
ALTER FUNCTION central.replicate_customers() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_store() SECURITY DEFINER;
ALTER FUNCTION central.replicate_store() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_product() SECURITY DEFINER;
ALTER FUNCTION central.replicate_product() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_category() SECURITY DEFINER;
ALTER FUNCTION central.replicate_category() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_role() SECURITY DEFINER;
ALTER FUNCTION central.replicate_role() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_supplier() SECURITY DEFINER;
ALTER FUNCTION central.replicate_supplier() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_orders() SECURITY DEFINER;
ALTER FUNCTION central.replicate_orders() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_order_items() SECURITY DEFINER;
ALTER FUNCTION central.replicate_order_items() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_payments() SECURITY DEFINER;
ALTER FUNCTION central.replicate_payments() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_inventory() SECURITY DEFINER;
ALTER FUNCTION central.replicate_inventory() SET search_path = pg_catalog;
ALTER FUNCTION central.replicate_audit() SECURITY DEFINER;
ALTER FUNCTION central.replicate_audit() SET search_path = pg_catalog;

-- ==================================================
-- 5. INDEXES (Central + Nodes)
-- ==================================================
-- Central Indexes
CREATE INDEX IF NOT EXISTS idx_cities_name ON central.Cities(name);
CREATE INDEX IF NOT EXISTS idx_stores_city_id ON central.Stores(city_id);
CREATE INDEX IF NOT EXISTS idx_products_sku ON central.Products(sku);
CREATE INDEX IF NOT EXISTS idx_inventory_product_store ON central.Inventory(product_id, store_id);
CREATE INDEX IF NOT EXISTS idx_orders_store_id ON central.Orders(store_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON central.Order_Items(order_id);

-- Karachi Indexes
CREATE INDEX IF NOT EXISTS idx_karachi_orders_store_id ON karachi.Orders(store_id);
CREATE INDEX IF NOT EXISTS idx_karachi_order_items_order_id ON karachi.Order_Items(order_id);
CREATE INDEX IF NOT EXISTS idx_karachi_inventory_product_store ON karachi.Inventory(product_id, store_id);

-- Lahore Indexes
CREATE INDEX IF NOT EXISTS idx_lahore_orders_store_id ON lahore.Orders(store_id);
CREATE INDEX IF NOT EXISTS idx_lahore_order_items_order_id ON lahore.Order_Items(order_id);
CREATE INDEX IF NOT EXISTS idx_lahore_inventory_product_store ON lahore.Inventory(product_id, store_id);

-- ==================================================
-- 5b. GLOBAL VIEWS
-- A global query reads these and does not name karachi or lahore.
-- ==================================================
CREATE OR REPLACE VIEW central.all_orders AS
SELECT 'karachi'::TEXT AS node, o.*
FROM karachi.orders o
UNION ALL
SELECT 'lahore'::TEXT AS node, o.*
FROM lahore.orders o;

CREATE OR REPLACE VIEW central.all_customers AS
SELECT 'karachi'::TEXT AS node, c.*
FROM karachi.customers c
UNION ALL
SELECT 'lahore'::TEXT AS node, c.*
FROM lahore.customers c;

CREATE OR REPLACE VIEW central.all_payments AS
SELECT 'karachi'::TEXT AS node, p.*
FROM karachi.payments p
UNION ALL
SELECT 'lahore'::TEXT AS node, p.*
FROM lahore.payments p;

CREATE OR REPLACE VIEW central.all_inventory AS
SELECT 'karachi'::TEXT AS node, i.*
FROM karachi.inventory i
UNION ALL
SELECT 'lahore'::TEXT AS node, i.*
FROM lahore.inventory i;

CREATE OR REPLACE VIEW central.product_sales AS
SELECT
  p.id AS product_id,
  p.name AS product_name,
  COALESCE(s.total_sales, 0)::NUMERIC(14,2) AS total_sales
FROM central.products p
LEFT JOIN (
  SELECT product_id, SUM(quantity * price) AS total_sales
  FROM (
    SELECT product_id, quantity, price FROM karachi.order_items
    UNION ALL
    SELECT product_id, quantity, price FROM lahore.order_items
  ) items
  GROUP BY product_id
) s ON s.product_id = p.id;

-- ==================================================
-- 6. SECURITY: Roles & Permissions
-- ==================================================
DO $$
BEGIN
  CREATE ROLE karachi_readonly NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;
DO $$
BEGIN
  CREATE ROLE lahore_readonly NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;
DO $$
BEGIN
  CREATE ROLE central_readonly NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END;
$$;

GRANT USAGE ON SCHEMA karachi TO karachi_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA karachi TO karachi_readonly;
GRANT USAGE ON SCHEMA lahore TO lahore_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA lahore TO lahore_readonly;
GRANT USAGE ON SCHEMA central TO central_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA central TO central_readonly;

-- Group roles above cannot log in. These users can.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'karachi_reader') THEN
    CREATE ROLE karachi_reader LOGIN PASSWORD 'karachi_read';
  ELSE
    ALTER ROLE karachi_reader LOGIN PASSWORD 'karachi_read';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lahore_reader') THEN
    CREATE ROLE lahore_reader LOGIN PASSWORD 'lahore_read';
  ELSE
    ALTER ROLE lahore_reader LOGIN PASSWORD 'lahore_read';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'central_reader') THEN
    CREATE ROLE central_reader LOGIN PASSWORD 'central_read';
  ELSE
    ALTER ROLE central_reader LOGIN PASSWORD 'central_read';
  END IF;
END;
$$;

GRANT karachi_readonly TO karachi_reader;
GRANT lahore_readonly TO lahore_reader;
GRANT central_readonly TO central_reader;

-- ==================================================
-- 7. BACKUP / RESTORE
-- ==================================================
-- Run these examples from a shell, not from psql:
-- pg_dump -n karachi pos_ddb > karachi_backup.sql
-- pg_dump -n lahore pos_ddb > lahore_backup.sql
-- pg_dump -n central pos_ddb > central_backup.sql
-- psql pos_ddb < karachi_backup.sql

-- ==================================================
-- 8. SAMPLE DISTRIBUTED QUERIES
-- ==================================================
-- Local query (Karachi orders)
SELECT o.id, o.order_date, o.total_amount, c.name AS customer_name
FROM karachi.Orders o
JOIN karachi.Customers c ON o.customer_id=c.id;

-- Global query (total sales per product). The view unions both cities.
SELECT product_id, product_name, total_sales
FROM central.product_sales
ORDER BY total_sales DESC;

-- ==================================================
-- 9. Stored Procedure
-- ==================================================
-- ProcessOrder

-- Drop the old 4-argument function so the new payment argument is not an overload.
DROP FUNCTION IF EXISTS central.ProcessOrder(INT, INT, JSONB, INT);

CREATE OR REPLACE FUNCTION central.ProcessOrder(
    p_store_id INT,
    p_customer_id INT,
    p_items JSONB,
    p_created_by INT,
    p_payment_method VARCHAR DEFAULT 'Cash'
) RETURNS UUID AS $$
DECLARE
    v_global_order_id UUID := gen_random_uuid();
    v_total_amount NUMERIC := 0;
    v_item JSONB;
    v_order_id INT;
    v_store_order_id INT;
    v_inventory_id INT;
    v_store_city_id INT;
    v_customer_city_id INT;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Order items must be a JSON array';
  END IF;
  IF jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'An order must contain at least one item';
  END IF;
  IF p_payment_method NOT IN ('Cash', 'Card', 'Online') THEN
    RAISE EXCEPTION 'Payment method must be Cash, Card, or Online';
  END IF;

  SELECT city_id INTO v_store_city_id
  FROM central.Stores
  WHERE id = p_store_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Store % does not exist', p_store_id;
  END IF;

  SELECT city_id INTO v_customer_city_id
  FROM central.Customers
  WHERE id = p_customer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer % does not exist', p_customer_id;
  END IF;

  IF v_store_city_id IS DISTINCT FROM v_customer_city_id THEN
    RAISE EXCEPTION 'Customer % is in a different city from store %', p_customer_id, p_store_id;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    IF COALESCE((v_item->>'quantity')::INT, 0) <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be positive';
    END IF;
    IF COALESCE((v_item->>'price')::NUMERIC, -1) < 0 THEN
      RAISE EXCEPTION 'Item price cannot be negative';
    END IF;
    v_total_amount := v_total_amount + (v_item->>'quantity')::NUMERIC * (v_item->>'price')::NUMERIC;
  END LOOP;

  PERFORM pg_advisory_xact_lock(1, p_store_id);
  SELECT COALESCE(MAX(store_order_id), 0) + 1 INTO v_store_order_id
  FROM central.Order_Mapping
  WHERE store_id = p_store_id;

  INSERT INTO central.Order_Mapping(
      store_id, store_order_id, customer_id, global_order_id, created_by, updated_by
  )
  VALUES (
      p_store_id,
      v_store_order_id,
      p_customer_id,
      v_global_order_id,
      p_created_by,
      p_created_by
  );

  INSERT INTO central.Orders(
      global_order_id, store_id, customer_id, total_amount, created_by, updated_by
  )
  VALUES (
      v_global_order_id, p_store_id, p_customer_id, v_total_amount, p_created_by, p_created_by
  )
  RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO central.Order_Items(
        order_id, product_id, quantity, price, created_by, updated_by
    )
    VALUES (
        v_order_id,
        (v_item->>'product_id')::INT,
        (v_item->>'quantity')::INT,
        (v_item->>'price')::NUMERIC,
        p_created_by,
        p_created_by
    );

    UPDATE central.Inventory
    SET quantity = quantity - (v_item->>'quantity')::INT,
        updated_at = now(),
        updated_by = p_created_by
    WHERE product_id = (v_item->>'product_id')::INT
      AND store_id = p_store_id
      AND quantity >= (v_item->>'quantity')::INT
    RETURNING id INTO v_inventory_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Insufficient inventory for product % at store %',
        v_item->>'product_id', p_store_id;
    END IF;
  END LOOP;

  INSERT INTO central.Payments(
      global_order_id, amount, method, status, created_by, updated_by
  )
  VALUES (
      v_global_order_id, v_total_amount, p_payment_method, 'Paid', p_created_by, p_created_by
  );

  RETURN v_global_order_id;
END;
$$ LANGUAGE plpgsql;

-- Example invocation after adding matching store, customer, product, and inventory rows:
-- SELECT central.ProcessOrder(
--     1,
--     10,
--     '[{"product_id":1,"quantity":2,"price":100},{"product_id":2,"quantity":1,"price":200}]'::jsonb,
--     1,
--     'Cash'
-- );

-- Performance Monitoring
-- Before querying this view, add pg_stat_statements to shared_preload_libraries
-- in postgresql.conf and restart PostgreSQL:
-- SELECT * FROM pg_stat_statements LIMIT 10;

-- ==================================================
-- NEXT: load realistic volume with seed_realistic_data.sql
--   psql -U postgres -d pos_ddb -f seed_realistic_data.sql
-- ==================================================