# DOTMS

Distributed OmniCommerce Transaction Processing System. A point-of-sale database for a grocery chain with branches in Karachi and Lahore.

Staff sign in through the web app. The account decides the store and the city. The browser never picks a database node. Every write goes to the `central` schema, and triggers copy the row into the Karachi or Lahore fragment that should hold it.

## Roles

| Role | What they open | Scope |
|---|---|---|
| Super Admin | Sales, products, stores, users | Both cities |
| Accountant | Sales report | Both cities, or one city if the account is tied to Karachi or Lahore |
| Store Manager | Register, today's orders, stock | One store |
| Cashier | Register and today's orders | One store |
| Inventory Clerk | Stock receiving | One store |

Checkout calls `central.ProcessOrder`. Prices come from `central.products`, not from the browser. A sale is stored on the city node that owns the store, and stock for that store is reduced there.

The sales report reads `central.product_sales`, which unions order lines from both cities. **Total** is the rupee value. **Total sales** is the number of units sold. A city accountant sees only that city's columns.

## How the database is split

PostgreSQL holds three schemas in one database:

- `central` is the only place the app writes. Cities, users, the product catalog, and the order map stay here.
- `karachi` and `lahore` are horizontal fragments. Stores, customers, orders, order lines, payments, and inventory live on the city that owns them.
- Products, categories, roles, and suppliers are copied to both cities.
- A store is copied only to its own city. Moving a store deletes the old city's copy, then inserts the row into the new city.

`schema_level.sql` is the schema this app uses.

## Run the app

PostgreSQL has to be running, with the database named in `server/.env` already loaded.

```
DATABASE_URL=postgres://postgres:postgres@localhost:5432/pos_ddb
SESSION_SECRET=change-me
PORT=4000
```

The presentation database on this machine is `pos_ddb_bench_100k_20261013_6f3a1c`. Point `DATABASE_URL` at that name to open the large load. `server/.env` is not committed.

Install once, then start the API and the site in two terminals:

```
cd server
npm install
npm run dev
```

```
cd web
npm install
npm run dev
```

On PowerShell, use `npm.cmd run dev` if script execution is disabled. The API listens on http://localhost:4000. The site is http://localhost:5173 and proxies `/api` to the API.

## Load the database

`schema_level.sql` creates `pos_ddb`, the `pgcrypto` extension, the three schemas, the triggers, and `central.ProcessOrder`. Run it with `psql`.

`seed_realistic_data.sql` loads stores, staff, shoppers, and sales. At the top of that file, three settings control the size:

- `seed.orders` — default `10000`. The full setting described in the file header is `9000000`.
- `seed.customers` — default `250000`.
- `seed.batch` — default `200000`.

The 100k bench load used for the demo has 30 stores, 166 products, 250,000 shoppers, and 100,000 orders. Seeded sale dates run from 15 January 2023 through 8 April 2026, so **Today** can be empty on a later date. The sales report is where that volume shows.

Running the seed truncates the current rows in `pos_ddb`.

## Demo sign-ins

Every seeded password is `Demo@12345`.

| Username | Role | Lands on |
|---|---|---|
| `hq.admin` | Super Admin | Head office, both cities |
| `hq.accounts1` | Accountant | Sales for both cities |
| `khi.accounts` | Accountant | Karachi sales only |
| `lhe.accounts` | Accountant | Lahore sales only |
| `khinnz01.cashier1` | Cashier | Imtiaz Super Market - North Nazimabad, Karachi |
| `khinnz01.manager` | Store Manager | Same Karachi store, plus stock |
| `khinnz01.stock` | Inventory Clerk | Stock at that Karachi store |
| `lheglb01.cashier1` | Cashier | Al-Fatah - Gulberg III, Lahore |

`hq.accounts1` through `hq.accounts10` are head-office accountants. A fresh run of `seed_realistic_data.sql` creates `hq.admin` and the store staff. It creates the Accountant role and does not create those accountant logins.

## Layout

```
schema_level.sql          database design
seed_realistic_data.sql   bulk load
server/                   Express API
web/                      React + Vite
```
