-- ==================================================
-- REALISTIC BULK SEED for pos_ddb
-- Run AFTER schema_level.sql:
--   psql -U postgres -d pos_ddb -f seed_realistic_data.sql
--
-- Default load is ~50 million rows in CENTRAL
-- (9M orders + 9M mappings + ~22.5M items + 9M payments + master data).
-- Karachi/Lahore copies add more physical rows on top.
--
-- Expect 1-3 hours and ~20-40 GB disk on a typical laptop.
-- Test first with 100000 orders (a few minutes).
-- ==================================================

\c pos_ddb

SET client_min_messages = NOTICE;
SET synchronous_commit = off;
SET work_mem = '256MB';
SET maintenance_work_mem = '1GB';
SET random_page_cost = 1.1;

-- >>> EDIT THESE THREE LINES <<<
SELECT set_config('seed.orders',    '10000', false);  -- 100000 to test, 9000000 for ~50M rows
SELECT set_config('seed.customers', '250000',  false);
SELECT set_config('seed.batch',     '200000',  false);

SET search_path = central, public;

-- --------------------------------------------------
-- Disable replication while bulk-loading
-- --------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT n.nspname, c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('central', 'karachi', 'lahore')
      AND c.relkind = 'r'
  LOOP
    EXECUTE format('ALTER TABLE %I.%I DISABLE TRIGGER ALL', r.nspname, r.relname);
  END LOOP;
END;
$$;

TRUNCATE TABLE
  central.order_items,
  central.payments,
  central.orders,
  central.order_mapping,
  central.inventory,
  central.customers,
  central.users,
  central.stores,
  central.products,
  central.suppliers,
  central.categories,
  central.roles,
  central.audit_logs
RESTART IDENTITY CASCADE;

TRUNCATE TABLE
  karachi.order_items, karachi.payments, karachi.orders, karachi.inventory,
  karachi.customers, karachi.stores, karachi.products, karachi.suppliers,
  karachi.categories, karachi.roles
RESTART IDENTITY CASCADE;

TRUNCATE TABLE
  lahore.order_items, lahore.payments, lahore.orders, lahore.inventory,
  lahore.customers, lahore.stores, lahore.products, lahore.suppliers,
  lahore.categories, lahore.roles
RESTART IDENTITY CASCADE;

INSERT INTO central.cities (name)
VALUES ('Karachi'), ('Lahore')
ON CONFLICT (name) DO NOTHING;

-- ==================================================
-- Master data that looks like a Pakistan grocery chain
-- ==================================================
DO $$
DECLARE
  v_khi INT;
  v_lhe INT;
  v_hash TEXT;
  v_first TEXT[] := ARRAY[
    'Ahmed','Ali','Hassan','Hussain','Omar','Usman','Bilal','Hamza','Zain','Ayaan',
    'Ibrahim','Yusuf','Faisal','Imran','Kamran','Shahid','Tariq','Naveed','Asad','Saad',
    'Farhan','Waleed','Arham','Subhan','Taha','Danish','Haris','Sami','Rehan','Junaid',
    'Kashif','Adnan','Salman','Fahad','Rizwan','Waqas','Zeeshan','Shahzaib','Ahsan','Umer',
    'Maryam','Ayesha','Fatima','Zainab','Hira','Sana','Amina','Iqra','Laiba','Areeba',
    'Maham','Noor','Sara','Khadija','Rabia','Nimra','Alina','Hania','Emaan','Dua',
    'Bisma','Anaya','Rania','Mehwish','Saba','Farah','Nadia','Saima','Hina','Asma',
    'Kinza','Zoya','Aiza','Maha','Anum','Fiza','Iman','Hoorain','Abeer','Mahnoor'
  ];
  v_last TEXT[] := ARRAY[
    'Khan','Ahmed','Ali','Malik','Sheikh','Qureshi','Hashmi','Syed','Raza','Hussain',
    'Butt','Cheema','Bajwa','Awan','Abbasi','Siddiqui','Farooqi','Javed','Iqbal','Rehman',
    'Zaman','Dar','Mirza','Chaudhry','Bhatti','Rajput','Mughal','Ansari','Qadri','Naqvi',
    'Zaidi','Kazmi','Gill','Warraich','Gondal','Rana','Yousaf','Nadeem','Akhtar','Saleem',
    'Anwar','Mehmood','Sharif','Bukhari','Gilani','Haider','Rizvi','Baig','Minhas','Lodhi'
  ];
  v_ops INT[] := ARRAY[300,301,302,303,305,312,313,315,316,320,321,322,323,330,331,333,334,340,341,345,346,347];
  v_mail TEXT[] := ARRAY['gmail.com','yahoo.com','hotmail.com','outlook.com','live.com'];
  v_n_cust INT := current_setting('seed.customers')::INT;
BEGIN
  SELECT id INTO v_khi FROM central.cities WHERE name = 'Karachi';
  SELECT id INTO v_lhe FROM central.cities WHERE name = 'Lahore';
  v_hash := crypt('Demo@12345', gen_salt('bf', 6));

  INSERT INTO central.roles (role_name, description) VALUES
    ('Super Admin', 'Full access across every city node'),
    ('Store Manager', 'Runs a single store and its staff'),
    ('Cashier', 'Checkout, payments, and receipts'),
    ('Inventory Clerk', 'Receiving and stock counts'),
    ('Accountant', 'Sales and payment reports');

  INSERT INTO central.categories (name, description) VALUES
    ('Beverages', 'Soft drinks, juices, water and energy drinks'),
    ('Dairy', 'Milk, yogurt, butter and cheese'),
    ('Bakery', 'Bread, buns and packed bakery'),
    ('Snacks', 'Chips, nimco and ready-to-eat snacks'),
    ('Biscuits & Confectionery', 'Biscuits, chocolate and sweets'),
    ('Tea & Coffee', 'Loose tea, tea bags and coffee'),
    ('Staples', 'Atta, rice, daal, sugar and salt'),
    ('Cooking Oil', 'Canola, sunflower, banaspati and ghee'),
    ('Spices', 'Masala, spices and recipe mixes'),
    ('Personal Care', 'Soap, shampoo, toothpaste and lotion'),
    ('Home Care', 'Detergent, dishwash and floor cleaners'),
    ('Baby Care', 'Diapers, wipes and formula'),
    ('Frozen', 'Frozen paratha, nuggets and vegetables'),
    ('Instant Food', 'Noodles, pasta and soup'),
    ('Health', 'OTC tablets, ORS and basic pharmacy');

  INSERT INTO central.suppliers (name, contact_info) VALUES
    ('Coca-Cola Beverages Pakistan', 'Karachi | 021-111-262-111'),
    ('PepsiCo Pakistan', 'Lahore | 042-111-737-742'),
    ('Nestle Pakistan', 'Sheikhupura | 042-111-637-853'),
    ('Unilever Pakistan', 'Karachi | 021-35664934'),
    ('Engro Foods / Olpers', 'Karachi | 021-111-211-211'),
    ('Tapal Tea (Pvt) Ltd', 'Karachi | 021-111-827-253'),
    ('Shan Foods', 'Karachi | 021-35065801'),
    ('National Foods Limited', 'Karachi | 021-32580390'),
    ('Dawn Foods', 'Karachi | 021-111-329-632'),
    ('Maple Leaf / Kausar Rice', 'Lahore | 042-35778711'),
    ('Dalda Foods', 'Karachi | 021-111-325-325'),
    ('Reckitt Benckiser Pakistan', 'Karachi | 021-35661871'),
    ('Procter & Gamble Pakistan', 'Karachi | 021-111-774-111'),
    ('Gourmet Foods', 'Lahore | 042-111-222-333'),
    ('Ismail Industries (CandyLand)', 'Karachi | 021-35065900');

  -- Packed SKUs you would actually see on a Pakistani mart shelf
  INSERT INTO central.products (sku, name, category_id, price)
  SELECT 'SKU-' || lpad(row_number() OVER (ORDER BY c.name, p.product_name)::TEXT, 5, '0'),
         p.product_name,
         c.id,
         p.price
  FROM (VALUES
    ('Beverages', 'Coca-Cola 1.5L', 180.00),
    ('Beverages', 'Coca-Cola 500ml', 80.00),
    ('Beverages', 'Coca-Cola 2.25L', 220.00),
    ('Beverages', 'Sprite 1.5L', 180.00),
    ('Beverages', 'Sprite 500ml', 80.00),
    ('Beverages', 'Fanta Orange 1.5L', 180.00),
    ('Beverages', 'Coke Zero 500ml', 90.00),
    ('Beverages', 'Pepsi 1.5L', 170.00),
    ('Beverages', 'Pepsi 500ml', 75.00),
    ('Beverages', '7UP 1.5L', 170.00),
    ('Beverages', 'Mountain Dew 1.5L', 175.00),
    ('Beverages', 'Gourmet Cola 1.5L', 130.00),
    ('Beverages', 'Pakola Ice Cream Soda 1L', 140.00),
    ('Beverages', 'Nestle Pure Life 1.5L', 90.00),
    ('Beverages', 'Aquafina 1.5L', 85.00),
    ('Beverages', 'Nestle Fruita Vitals Mango 1L', 220.00),
    ('Beverages', 'Slice Mango 1L', 210.00),
    ('Beverages', 'Rani Float Peach 240ml', 70.00),
    ('Beverages', 'Red Bull 250ml', 250.00),
    ('Beverages', 'Sting Energy 500ml', 90.00),
    ('Beverages', 'Rooh Afza 800ml', 320.00),
    ('Beverages', 'Shezan Mango Nectar 1L', 190.00),
    ('Dairy', 'Olpers Milk 1L', 290.00),
    ('Dairy', 'Olpers Milk 1.5L', 420.00),
    ('Dairy', 'Milkpak 1L', 285.00),
    ('Dairy', 'Nestle Everyday Liquid 1L', 310.00),
    ('Dairy', 'Nurpur Milk 1L', 280.00),
    ('Dairy', 'Prema Milk 1L', 270.00),
    ('Dairy', 'Olpers Cream 200ml', 180.00),
    ('Dairy', 'Nestle Yogurt 400g', 160.00),
    ('Dairy', 'Olpers Yogurt 400g', 155.00),
    ('Dairy', 'Nurpur Butter 200g', 420.00),
    ('Dairy', 'Nurpur Cheese Slices 200g', 480.00),
    ('Dairy', 'Tarang Tea Whitener 1L', 260.00),
    ('Dairy', 'Everyday Powder 400g', 890.00),
    ('Dairy', 'Haleeb Milk 1L', 275.00),
    ('Bakery', 'Dawn Bread Large', 180.00),
    ('Bakery', 'Dawn Bread Small', 120.00),
    ('Bakery', 'Bake Parlor Bread Large', 170.00),
    ('Bakery', 'Dawn Burger Bun 4pc', 140.00),
    ('Bakery', 'Dawn Hotdog Bun 4pc', 140.00),
    ('Bakery', 'Dawn Rusk 300g', 220.00),
    ('Bakery', 'English Oven Bread', 200.00),
    ('Snacks', 'Lays Masala 70g', 80.00),
    ('Snacks', 'Lays French Cheese 70g', 80.00),
    ('Snacks', 'Lays Salted 70g', 80.00),
    ('Snacks', 'Kurkure Chutney 60g', 70.00),
    ('Snacks', 'Kurkure Red Chilli 60g', 70.00),
    ('Snacks', 'Slanty Salted 60g', 50.00),
    ('Snacks', 'Super Crisp BBQ 50g', 40.00),
    ('Snacks', 'Cheetos Crunchy 70g', 80.00),
    ('Snacks', 'Kolson Slanty Chatkhara 60g', 55.00),
    ('Snacks', 'Gourmet Nimco Mix 200g', 180.00),
    ('Snacks', 'Kitchen Cuisine Mix Nimco 200g', 170.00),
    ('Snacks', 'Lays Wavy Mexican 70g', 80.00),
    ('Biscuits & Confectionery', 'Sooper Biscuits Family Pack', 160.00),
    ('Biscuits & Confectionery', 'Prince Biscuits Half Roll', 90.00),
    ('Biscuits & Confectionery', 'Rio Chocolate Half Roll', 90.00),
    ('Biscuits & Confectionery', 'Candi Biscuits Half Roll', 80.00),
    ('Biscuits & Confectionery', 'Peek Freans Gluco 3 in 1', 150.00),
    ('Biscuits & Confectionery', 'LU Zeera Plus 3 in 1', 150.00),
    ('Biscuits & Confectionery', 'LU TUC Original', 80.00),
    ('Biscuits & Confectionery', 'Oreo Original 133g', 220.00),
    ('Biscuits & Confectionery', 'KitKat 4 Finger', 120.00),
    ('Biscuits & Confectionery', 'Dairy Milk Fruit & Nut 38g', 150.00),
    ('Biscuits & Confectionery', 'Now Now Chocolate 24pc', 240.00),
    ('Biscuits & Confectionery', 'CandyLand ChocoJoy 24pc', 220.00),
    ('Biscuits & Confectionery', 'Novita Wafer 75g', 90.00),
    ('Biscuits & Confectionery', 'Bounty Twin', 160.00),
    ('Tea & Coffee', 'Tapal Danedar 430g', 980.00),
    ('Tea & Coffee', 'Tapal Danedar 900g', 1890.00),
    ('Tea & Coffee', 'Tapal Family Mixture 430g', 860.00),
    ('Tea & Coffee', 'Lipton Yellow Label 400g', 920.00),
    ('Tea & Coffee', 'Lipton Tea Bags 100s', 780.00),
    ('Tea & Coffee', 'Tapal Tezdam 475g', 890.00),
    ('Tea & Coffee', 'Vital Tea 400g', 720.00),
    ('Tea & Coffee', 'Nescafe Classic 50g', 620.00),
    ('Tea & Coffee', 'Nescafe Classic 100g', 1150.00),
    ('Tea & Coffee', 'Nescafe 3 in 1 10s', 280.00),
    ('Staples', 'Sunridge Atta 10kg', 1450.00),
    ('Staples', 'Sunridge Atta 5kg', 760.00),
    ('Staples', 'Bake Parlor Super Fine Atta 10kg', 1490.00),
    ('Staples', 'Guard Super Kernel Basmati 5kg', 2150.00),
    ('Staples', 'Falak Basmati Rice 5kg', 1980.00),
    ('Staples', 'Kainat 1121 Rice 5kg', 2050.00),
    ('Staples', 'Shakarganj Sugar 1kg', 170.00),
    ('Staples', 'National Salt Iodized 800g', 70.00),
    ('Staples', 'Shan Moong Daal 1kg', 380.00),
    ('Staples', 'Shan Masoor Daal 1kg', 360.00),
    ('Staples', 'National Chana Daal 1kg', 340.00),
    ('Staples', 'National White Chana 1kg', 390.00),
    ('Cooking Oil', 'Dalda Canola 5L', 2450.00),
    ('Cooking Oil', 'Dalda Sunflower 5L', 2550.00),
    ('Cooking Oil', 'Sufi Cooking Oil 5L', 2380.00),
    ('Cooking Oil', 'Meezan Canola 5L', 2420.00),
    ('Cooking Oil', 'Eva Canola 5L', 2490.00),
    ('Cooking Oil', 'Dalda Banaspati 5kg', 2290.00),
    ('Cooking Oil', 'Tallo Banaspati 5kg', 2150.00),
    ('Cooking Oil', 'Olitalia Olive Oil 500ml', 1650.00),
    ('Spices', 'Shan Biryani Masala 50g', 90.00),
    ('Spices', 'Shan Bombay Biryani 50g', 90.00),
    ('Spices', 'Shan Chicken Tikka 50g', 85.00),
    ('Spices', 'Shan Achar Gosht 50g', 85.00),
    ('Spices', 'National Biryani Masala 50g', 80.00),
    ('Spices', 'National Korma Masala 50g', 80.00),
    ('Spices', 'Shan Red Chilli Powder 200g', 280.00),
    ('Spices', 'National Haldi 200g', 220.00),
    ('Spices', 'Shan Dhania Powder 200g', 240.00),
    ('Spices', 'National Garam Masala 50g', 95.00),
    ('Spices', 'Mitchells Mango Chutney 420g', 310.00),
    ('Spices', 'National Mango Pickle 320g', 260.00),
    ('Personal Care', 'Lifebuoy Total Soap 130g', 90.00),
    ('Personal Care', 'Lux Soft Touch Soap 130g', 95.00),
    ('Personal Care', 'Safeguard Soap 130g', 100.00),
    ('Personal Care', 'Dettol Soap Original 130g', 110.00),
    ('Personal Care', 'Colgate Maximum Cavity 150g', 240.00),
    ('Personal Care', 'Sensodyne Repair 75ml', 520.00),
    ('Personal Care', 'Sunsilk Black Shine 185ml', 390.00),
    ('Personal Care', 'Pantene Smooth 185ml', 420.00),
    ('Personal Care', 'Head & Shoulders 185ml', 480.00),
    ('Personal Care', 'Dove Beauty Bar 135g', 180.00),
    ('Personal Care', 'Nivea Soft 100ml', 320.00),
    ('Personal Care', 'Fair & Lovely 50g', 210.00),
    ('Personal Care', 'Gillette Blue 2 5s', 280.00),
    ('Home Care', 'Surf Excel 2kg', 890.00),
    ('Home Care', 'Ariel 2kg', 920.00),
    ('Home Care', 'Bonus Tristar 2kg', 640.00),
    ('Home Care', 'Brite 2kg', 610.00),
    ('Home Care', 'Harpic Power Plus 500ml', 280.00),
    ('Home Care', 'Dettol Antiseptic 500ml', 420.00),
    ('Home Care', 'Vim Dishwash 500ml', 210.00),
    ('Home Care', 'Max Dishwash 500ml', 160.00),
    ('Home Care', 'Finish Dishwasher Tablets 26s', 1450.00),
    ('Home Care', 'Mortein Coil 10s', 140.00),
    ('Home Care', 'Cobra Coil 10s', 90.00),
    ('Home Care', 'Tissue Supreme 150 Pulls', 180.00),
    ('Baby Care', 'Pampers Baby Dry Jumbo S4 36s', 1890.00),
    ('Baby Care', 'Canbebe Midi 36s', 1650.00),
    ('Baby Care', 'Johnson Baby Lotion 200ml', 480.00),
    ('Baby Care', 'Johnson Baby Shampoo 200ml', 460.00),
    ('Baby Care', 'Nestle Nido 1+ 400g', 1450.00),
    ('Baby Care', 'Morinaga BF-1 400g', 1680.00),
    ('Baby Care', 'Wet Wipes 80s', 220.00),
    ('Frozen', 'K&Ns Chicken Nuggets 1kg', 1450.00),
    ('Frozen', 'K&Ns Chicken Tenders 1kg', 1580.00),
    ('Frozen', 'Menu Paratha 5pc', 280.00),
    ('Frozen', 'Dawn Paratha 5pc', 260.00),
    ('Frozen', 'K&Ns Qeema 1kg', 980.00),
    ('Frozen', 'Seasons Frozen Mix Veg 400g', 320.00),
    ('Frozen', 'Igloo Vanilla 1L', 420.00),
    ('Frozen', 'Walls Magnum Classic', 180.00),
    ('Instant Food', 'Knorr Noodles Chicken 66g', 70.00),
    ('Instant Food', 'Knorr Noodles Chatpata 66g', 70.00),
    ('Instant Food', 'Maggi Noodles Masala 66g', 70.00),
    ('Instant Food', 'Kolson Spaghetti 500g', 280.00),
    ('Instant Food', 'Bake Parlor Pasta 500g', 260.00),
    ('Instant Food', 'Knorr Chicken Cube 8s', 150.00),
    ('Instant Food', 'National Recipe Mix Karahi 50g', 80.00),
    ('Instant Food', 'Shan Haleem Mix 300g', 220.00),
    ('Health', 'Panadol 500mg 20s', 90.00),
    ('Health', 'Disprin 30s', 80.00),
    ('Health', 'ORS Sachet 10s', 180.00),
    ('Health', 'Gaviscon 150ml', 420.00),
    ('Health', 'Eno Sachet 6s', 160.00),
    ('Health', 'Brufen 400mg 20s', 140.00),
    ('Health', 'Polyfax Skin Ointment 20g', 190.00)
  ) AS p(category_name, product_name, price)
  JOIN central.categories c ON c.name = p.category_name;

  INSERT INTO central.stores (city_id, name, code) VALUES
    (v_khi, 'Imtiaz Super Market - North Nazimabad', 'KHI-NNZ-01'),
    (v_khi, 'Chase Up - Tariq Road', 'KHI-TRQ-02'),
    (v_khi, 'Naheed Super Market - Bahadurabad', 'KHI-BHD-03'),
    (v_khi, 'Bin Hashim - Gulshan-e-Iqbal', 'KHI-GSH-04'),
    (v_khi, 'Carrefour - Dolmen Mall Clifton', 'KHI-CLT-05'),
    (v_khi, 'Metro - Korangi Crossing', 'KHI-KRG-06'),
    (v_khi, 'Imtiaz Super Market - DHA Phase 6', 'KHI-DHA-07'),
    (v_khi, 'Al-Fatah - Saddar', 'KHI-SDR-08'),
    (v_khi, 'Chase Value - Malir Halt', 'KHI-MLR-09'),
    (v_khi, 'Agha''s Super Market - Boat Basin', 'KHI-CLT-10'),
    (v_khi, 'Naheed - Defence Phase 4', 'KHI-DHA-11'),
    (v_khi, 'Imtiaz - Gulistan-e-Johar', 'KHI-JHR-12'),
    (v_khi, 'Chase Up - Hyderi', 'KHI-HYD-13'),
    (v_khi, 'Bin Hashim - North Karachi', 'KHI-NKH-14'),
    (v_khi, 'Carrefour - Lucky One Mall', 'KHI-GSH-15'),
    (v_lhe, 'Al-Fatah - Gulberg III', 'LHE-GLB-01'),
    (v_lhe, 'Carrefour - Packages Mall', 'LHE-PKG-02'),
    (v_lhe, 'Imtiaz Super Market - Johar Town', 'LHE-JHT-03'),
    (v_lhe, 'Metro - Thokar Niaz Baig', 'LHE-TNB-04'),
    (v_lhe, 'Chase Up - Liberty Market', 'LHE-LBT-05'),
    (v_lhe, 'Naheed - DHA Phase 5 Lahore', 'LHE-DHA-06'),
    (v_lhe, 'Al-Fatah - Model Town', 'LHE-MDT-07'),
    (v_lhe, 'Hyperstar - Fortress Stadium', 'LHE-FRT-08'),
    (v_lhe, 'Imtiaz - Wapda Town', 'LHE-WPD-09'),
    (v_lhe, 'Chase Value - Township', 'LHE-TWN-10'),
    (v_lhe, 'Carrefour - Mall of Lahore', 'LHE-CAN-11'),
    (v_lhe, 'Al-Fatah - DHA Y Block', 'LHE-DHA-12'),
    (v_lhe, 'Bin Hashim - Garden Town', 'LHE-GDN-13'),
    (v_lhe, 'Naheed - Bahria Town Lahore', 'LHE-BHR-14'),
    (v_lhe, 'Imtiaz Super Market - Cantt', 'LHE-CNT-15');

  INSERT INTO central.users (username, email, password_hash, full_name, role_id, store_id)
  SELECT
    lower(regexp_replace(s.code, '[^A-Za-z0-9]', '', 'g')) || '.' || staff.kind,
    lower(staff.kind) || '.' || lower(replace(s.code, ' ', '')) || '@posmart.pk',
    v_hash,
    staff.names[1 + ((s.id + staff.ord) % array_length(staff.names, 1))],
    r.id,
    s.id
  FROM central.stores s
  CROSS JOIN (VALUES
    (1, 'manager', 'Store Manager', ARRAY['Usman Malik','Hira Chaudhry','Faisal Sheikh','Ayesha Qureshi']),
    (2, 'cashier1', 'Cashier', ARRAY['Bilal Ahmed','Laiba Raza','Hamza Butt','Iqra Siddiqui']),
    (3, 'cashier2', 'Cashier', ARRAY['Saad Javed','Maham Ali','Rehan Awan','Noor Hashmi']),
    (4, 'stock', 'Inventory Clerk', ARRAY['Kashif Dar','Sana Mirza','Waqas Gondal','Hina Baig'])
  ) AS staff(ord, kind, role_name, names)
  JOIN central.roles r ON r.role_name = staff.role_name;

  INSERT INTO central.users (username, email, password_hash, full_name, role_id, store_id)
  VALUES (
    'hq.admin',
    'admin@posmart.pk',
    v_hash,
    'Head Office Admin',
    (SELECT id FROM central.roles WHERE role_name = 'Super Admin'),
    NULL
  );

  -- Shoppers first in Karachi (60%), then Lahore (40%) so IDs stay contiguous per city
  INSERT INTO central.customers (city_id, name, phone, email, created_by, updated_by)
  SELECT
    CASE WHEN g <= (v_n_cust * 3 / 5) THEN v_khi ELSE v_lhe END,
    v_first[1 + ((g * 17) % array_length(v_first, 1))] || ' ' ||
    v_last[1 + ((g * 31) % array_length(v_last, 1))],
    '0' || v_ops[1 + (g % array_length(v_ops, 1))]::TEXT ||
      lpad(g::TEXT, 7, '0'),
    CASE WHEN g % 9 = 0 THEN NULL
         ELSE lower(v_first[1 + ((g * 17) % array_length(v_first, 1))]) || '.' ||
              lower(v_last[1 + ((g * 31) % array_length(v_last, 1))]) ||
              g::TEXT || '@' || v_mail[1 + (g % array_length(v_mail, 1))]
    END,
    1, 1
  FROM generate_series(1, v_n_cust) AS g;

  INSERT INTO central.inventory (
    product_id, store_id, quantity, purchase_price, created_by, updated_by
  )
  SELECT
    p.id,
    s.id,
    40 + ((p.id * 13 + s.id * 7) % 420),
    round(p.price * 0.74, 2),
    1, 1
  FROM central.products p
  CROSS JOIN central.stores s;

  RAISE NOTICE 'Master data ready: % products, % stores, % customers',
    (SELECT count(*) FROM central.products),
    (SELECT count(*) FROM central.stores),
    (SELECT count(*) FROM central.customers);
END;
$$;

-- ==================================================
-- Batched order / item / payment load (~50M rows)
-- ==================================================
CREATE OR REPLACE PROCEDURE central.seed_bulk_transactions(p_orders BIGINT, p_batch INT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_from BIGINT;
  v_to BIGINT;
  v_n_stores INT;
  v_n_products INT;
  v_n_users INT;
  v_khi_cust INT;
  v_lhe_cust_start INT;
  v_lhe_cust INT;
  v_khi INT;
  v_n_lines BIGINT;
BEGIN
  SELECT count(*) INTO v_n_stores FROM central.stores;
  SELECT count(*) INTO v_n_products FROM central.products;
  SELECT count(*) INTO v_n_users FROM central.users;
  SELECT id INTO v_khi FROM central.cities WHERE name = 'Karachi';
  SELECT count(*) INTO v_khi_cust FROM central.customers WHERE city_id = v_khi;
  SELECT coalesce(min(id), 1) INTO v_lhe_cust_start FROM central.customers WHERE city_id <> v_khi;
  SELECT count(*) INTO v_lhe_cust FROM central.customers WHERE city_id <> v_khi;

  IF v_n_stores = 0 OR v_n_products = 0 OR v_khi_cust = 0 THEN
    RAISE EXCEPTION 'Master data missing. Re-run the seed from the top.';
  END IF;

  v_from := 1;
  WHILE v_from <= p_orders LOOP
    v_to := LEAST(v_from + p_batch - 1, p_orders);

    INSERT INTO central.order_mapping (
      id, created_at, updated_at, created_by, updated_by,
      global_order_id, store_id, store_order_id, customer_id, order_time
    )
    SELECT
      g,
      ts, ts,
      1 + ((g + s.id) % v_n_users),
      1 + ((g + s.id) % v_n_users),
      gen_random_uuid(),
      s.id,
      1 + ((g - 1) / v_n_stores),
      CASE WHEN s.city_id = v_khi
           THEN 1 + ((g * 13) % v_khi_cust)
           ELSE v_lhe_cust_start + ((g * 17) % v_lhe_cust)
      END,
      ts
    FROM generate_series(v_from, v_to) AS g
    JOIN central.stores s
      ON s.id = 1 + ((g - 1) % v_n_stores)
    CROSS JOIN LATERAL (
      SELECT timestamptz '2023-01-15 09:10:00+05'
           + (((g * 997) % 1180) * interval '1 day')
           + (((g * 13) % 11) * interval '1 hour')
           + (((g * 29) % 50) * interval '1 minute')
    ) AS t(ts);

    INSERT INTO central.orders (
      id, created_at, updated_at, created_by, updated_by,
      global_order_id, store_id, customer_id, order_date, total_amount,
      status, tracking_code
    )
    SELECT
      m.id, m.order_time, m.order_time, m.created_by, m.updated_by,
      m.global_order_id, m.store_id, m.customer_id, m.order_time, 0,
      CASE
        WHEN m.id % 100 < 86 THEN 'Completed'
        WHEN m.id % 100 < 93 THEN 'Pending'
        WHEN m.id % 100 < 98 THEN 'Cancelled'
        ELSE 'Refunded'
      END,
      'TRK-' || to_char(m.order_time, 'YYYYMMDD') || '-' || lpad(m.id::TEXT, 8, '0')
    FROM central.order_mapping m
    WHERE m.id BETWEEN v_from AND v_to;

    INSERT INTO central.order_items (
      created_at, updated_at, created_by, updated_by,
      order_id, product_id, quantity, price
    )
    SELECT
      o.order_date, o.order_date, o.created_by, o.updated_by,
      o.id,
      p.id,
      CASE
        WHEN (o.id + line.n) % 11 = 0 THEN 4
        WHEN (o.id + line.n) % 7 = 0 THEN 3
        WHEN (o.id + line.n) % 3 = 0 THEN 2
        ELSE 1
      END,
      p.price
    FROM central.orders o
    CROSS JOIN LATERAL generate_series(1, 1 + (o.id % 4)) AS line(n)
    JOIN central.products p
      ON p.id = 1 + ((o.id * 17 + line.n * 31) % v_n_products)
    WHERE o.id BETWEEN v_from AND v_to;

    UPDATE central.orders o
    SET total_amount = s.basket
    FROM (
      SELECT order_id, round(sum(quantity * price), 2) AS basket
      FROM central.order_items
      WHERE order_id BETWEEN v_from AND v_to
      GROUP BY order_id
    ) s
    WHERE o.id = s.order_id
      AND o.id BETWEEN v_from AND v_to;

    INSERT INTO central.payments (
      created_at, updated_at, created_by, updated_by,
      global_order_id, amount, method, status
    )
    SELECT
      o.order_date, o.order_date, o.created_by, o.updated_by,
      o.global_order_id,
      o.total_amount,
      CASE
        WHEN o.id % 20 < 11 THEN 'Cash'
        WHEN o.id % 20 < 17 THEN 'Card'
        ELSE 'Online'
      END,
      CASE o.status
        WHEN 'Completed' THEN 'Paid'
        WHEN 'Pending' THEN 'Pending'
        WHEN 'Cancelled' THEN 'Failed'
        ELSE 'Refunded'
      END
    FROM central.orders o
    WHERE o.id BETWEEN v_from AND v_to;

    GET DIAGNOSTICS v_n_lines = ROW_COUNT;
    RAISE NOTICE 'Seeded orders % to % (payments in batch: %)', v_from, v_to, v_n_lines;
    v_from := v_to + 1;
    COMMIT;
  END LOOP;

  PERFORM setval('central.order_mapping_id_seq', p_orders, true);
  PERFORM setval('central.orders_id_seq', p_orders, true);
  PERFORM setval(
    'central.order_items_id_seq',
    (SELECT coalesce(max(id), 1) FROM central.order_items),
    true
  );
  PERFORM setval(
    'central.payments_id_seq',
    (SELECT coalesce(max(id), 1) FROM central.payments),
    true
  );
END;
$$;

CALL central.seed_bulk_transactions(
  current_setting('seed.orders')::BIGINT,
  current_setting('seed.batch')::INT
);

-- ==================================================
-- Copy into Karachi / Lahore nodes (still no triggers)
-- ==================================================
CREATE OR REPLACE PROCEDURE central.seed_copy_region(p_schema TEXT, p_city TEXT, p_batch INT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_city INT;
  v_max BIGINT;
  v_from BIGINT := 1;
  v_to BIGINT;
BEGIN
  SELECT id INTO v_city FROM central.cities WHERE name = p_city;
  EXECUTE format('TRUNCATE TABLE %I.order_items, %I.payments, %I.orders, %I.inventory, %I.customers, %I.stores, %I.products, %I.suppliers, %I.categories, %I.roles',
    p_schema, p_schema, p_schema, p_schema, p_schema, p_schema, p_schema, p_schema, p_schema, p_schema);

  EXECUTE format('INSERT INTO %I.categories SELECT * FROM central.categories', p_schema);
  EXECUTE format('INSERT INTO %I.roles SELECT * FROM central.roles', p_schema);
  EXECUTE format('INSERT INTO %I.products SELECT * FROM central.products', p_schema);
  EXECUTE format('INSERT INTO %I.suppliers SELECT * FROM central.suppliers', p_schema);
  EXECUTE format(
    'INSERT INTO %I.stores SELECT * FROM central.stores WHERE city_id = $1',
    p_schema
  ) USING v_city;
  EXECUTE format(
    'INSERT INTO %I.customers SELECT * FROM central.customers WHERE city_id = $1',
    p_schema
  ) USING v_city;
  EXECUTE format(
    'INSERT INTO %I.inventory i SELECT inv.* FROM central.inventory inv JOIN central.stores s ON s.id = inv.store_id WHERE s.city_id = $1',
    p_schema
  ) USING v_city;

  SELECT coalesce(max(id), 0) INTO v_max FROM central.orders;
  WHILE v_from <= v_max LOOP
    v_to := LEAST(v_from + p_batch - 1, v_max);
    EXECUTE format(
      $sql$
      INSERT INTO %I.orders
      SELECT o.*
      FROM central.orders o
      JOIN central.stores s ON s.id = o.store_id
      WHERE s.city_id = $1 AND o.id BETWEEN $2 AND $3
      $sql$, p_schema
    ) USING v_city, v_from, v_to;

    EXECUTE format(
      $sql$
      INSERT INTO %I.order_items
      SELECT oi.*
      FROM central.order_items oi
      JOIN central.orders o ON o.id = oi.order_id
      JOIN central.stores s ON s.id = o.store_id
      WHERE s.city_id = $1 AND o.id BETWEEN $2 AND $3
      $sql$, p_schema
    ) USING v_city, v_from, v_to;

    EXECUTE format(
      $sql$
      INSERT INTO %I.payments
      SELECT p.*
      FROM central.payments p
      JOIN central.order_mapping m ON m.global_order_id = p.global_order_id
      JOIN central.stores s ON s.id = m.store_id
      WHERE s.city_id = $1 AND m.id BETWEEN $2 AND $3
      $sql$, p_schema
    ) USING v_city, v_from, v_to;

    RAISE NOTICE '% copied order ids % to %', p_city, v_from, v_to;
    v_from := v_to + 1;
    COMMIT;
  END LOOP;
END;
$$;

CALL central.seed_copy_region('karachi', 'Karachi', current_setting('seed.batch')::INT);
CALL central.seed_copy_region('lahore', 'Lahore', current_setting('seed.batch')::INT);

CREATE INDEX IF NOT EXISTS idx_orders_order_date ON central.orders (order_date);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON central.orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_global_order ON central.payments (global_order_id);
CREATE INDEX IF NOT EXISTS idx_customers_city ON central.customers (city_id);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON central.customers (phone);

ANALYZE central.orders;
ANALYZE central.order_items;
ANALYZE central.payments;
ANALYZE central.order_mapping;
ANALYZE central.customers;
ANALYZE karachi.orders;
ANALYZE lahore.orders;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT n.nspname, c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('central', 'karachi', 'lahore')
      AND c.relkind = 'r'
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE TRIGGER ALL', r.nspname, r.relname);
  END LOOP;
END;
$$;

-- Sanity check: names, cities, basket sizes, methods
SELECT 'central.customers' AS tbl, count(*) AS rows FROM central.customers
UNION ALL SELECT 'central.products', count(*) FROM central.products
UNION ALL SELECT 'central.stores', count(*) FROM central.stores
UNION ALL SELECT 'central.orders', count(*) FROM central.orders
UNION ALL SELECT 'central.order_items', count(*) FROM central.order_items
UNION ALL SELECT 'central.payments', count(*) FROM central.payments
UNION ALL SELECT 'central.order_mapping', count(*) FROM central.order_mapping
UNION ALL SELECT 'karachi.orders', count(*) FROM karachi.orders
UNION ALL SELECT 'lahore.orders', count(*) FROM lahore.orders
ORDER BY 1;

SELECT name, phone, email FROM central.customers ORDER BY id LIMIT 8;
SELECT name, price FROM central.products ORDER BY id LIMIT 8;
SELECT s.name AS store, c.name AS customer, o.order_date, o.total_amount, o.status, o.tracking_code
FROM central.orders o
JOIN central.stores s ON s.id = o.store_id
JOIN central.customers c ON c.id = o.customer_id
ORDER BY o.id
LIMIT 8;
