import sqlite3
import os
import json
import random

OUT_DIR = "/Users/darianhickman/Documents/sqliteplutogrid/test_databases"
os.makedirs(OUT_DIR, exist_ok=True)

# 1. Complex DB
complex_db_path = os.path.join(OUT_DIR, "complex.sqlite")
if os.path.exists(complex_db_path):
    os.remove(complex_db_path)

conn = sqlite3.connect(complex_db_path)
cur = conn.cursor()

# Table 1: Special names & types
cur.execute('''
CREATE TABLE "1_orders" (
    "order id" INTEGER PRIMARY KEY AUTOINCREMENT,
    "customer name" TEXT NOT NULL,
    "email" TEXT,
    "amount" REAL DEFAULT 0.0,
    "status" TEXT CHECK(status IN ('pending', 'completed', 'cancelled')),
    "metadata json" TEXT,
    "large payload" TEXT,
    "created at" DATETIME DEFAULT CURRENT_TIMESTAMP,
    "is flagged" INTEGER DEFAULT 0
);
''')

cur.execute('CREATE INDEX "idx_orders_customer" ON "1_orders" ("customer name");')
cur.execute('CREATE INDEX "idx_orders_status_amount" ON "1_orders" ("status", "amount");')

# Table 2: Product inventory with hyphenated name
cur.execute('''
CREATE TABLE "Product-Inventory" (
    sku TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    category TEXT,
    price REAL,
    stock INTEGER,
    rating REAL,
    raw_specs TEXT
);
''')

# Table 3: Users
cur.execute('''
CREATE TABLE "users" (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    bio TEXT,
    avatar_url TEXT,
    score INTEGER DEFAULT 100
);
''')

# View 1
cur.execute('''
CREATE VIEW "v_top_orders" AS
SELECT "order id", "customer name", "amount", "status", "created at"
FROM "1_orders"
WHERE "amount" > 250.0;
''')

# View 2
cur.execute('''
CREATE VIEW "v_inventory_summary" AS
SELECT category, COUNT(*) as item_count, AVG(price) as avg_price, SUM(stock) as total_stock
FROM "Product-Inventory"
GROUP BY category;
''')

# Populate 1_orders (1200 rows)
statuses = ['pending', 'completed', 'cancelled']
sample_large_text = ("Lorem ipsum dolor sit amet, consectetur adipiscing elit. " * 50)

for i in range(1, 1201):
    meta = json.dumps({
        "order_num": i,
        "items": [
            {"sku": f"SKU-{random.randint(100, 999)}", "qty": random.randint(1, 5), "unit_price": round(random.uniform(10.0, 100.0), 2)}
            for _ in range(random.randint(1, 4))
        ],
        "shipping": {"city": "Austin", "state": "TX", "postal": "78701", "express": bool(i % 2 == 0)},
        "discount_applied": None if i % 3 == 0 else f"{i%15}%"
    }, indent=2)
    
    cur.execute('''
    INSERT INTO "1_orders" ("customer name", "email", "amount", "status", "metadata json", "large payload", "is flagged")
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (
        f"Customer {i}",
        f"user{i}@example.com" if i % 5 != 0 else None,
        round(random.uniform(5.0, 600.0), 2),
        statuses[i % len(statuses)],
        meta,
        f"Detailed audit log for order #{i}:\n" + sample_large_text if i % 10 == 0 else "Short note.",
        1 if i % 7 == 0 else 0
    ))

# Populate Product-Inventory (150 rows)
categories = ['Electronics', 'Books', 'Home & Kitchen', 'Apparel', 'Automotive']
for i in range(1, 151):
    cur.execute('''
    INSERT INTO "Product-Inventory" (sku, title, category, price, stock, rating, raw_specs)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (
        f"PROD-{i:04d}",
        f"Super Product {i} - Special Edition",
        categories[i % len(categories)],
        round(random.uniform(9.99, 999.99), 2),
        random.randint(0, 500),
        round(random.uniform(3.0, 5.0), 1),
        json.dumps({"warranty_months": 12, "weight_kg": round(random.uniform(0.2, 15.0), 2)})
    ))

# Populate users (50 rows)
for i in range(1, 51):
    cur.execute('''
    INSERT INTO "users" (username, bio, avatar_url, score)
    VALUES (?, ?, ?, ?)
    ''', (
        f"user_{i}",
        f"Bio for user {i}: SQLite enthusiast and data engineer." if i % 2 == 0 else None,
        f"https://avatars.example.com/{i}.png",
        random.randint(50, 1000)
    ))

conn.commit()
conn.close()

# 2. Empty DB
empty_db_path = os.path.join(OUT_DIR, "empty.sqlite")
if os.path.exists(empty_db_path):
    os.remove(empty_db_path)
conn_empty = sqlite3.connect(empty_db_path)
conn_empty.close()

print(f"Generated test databases in {OUT_DIR}:")
print(f" - {complex_db_path} ({os.path.getsize(complex_db_path) / 1024:.1f} KB)")
print(f" - {empty_db_path} ({os.path.getsize(empty_db_path)} bytes)")
