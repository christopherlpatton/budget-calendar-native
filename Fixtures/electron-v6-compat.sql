-- Canonical Electron-compatible v6 database fixture. It is applied to an empty SQLite file before Swift opens it.
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, color TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('purchase','bill','deposit','both')), is_builtin INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0, income_type TEXT CHECK(income_type IN ('salary','other') OR income_type IS NULL));
CREATE TABLE recurring_rules (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL CHECK(kind IN ('monthly_date','weekly','biweekly','monthly_nth')), anchor_date TEXT NOT NULL, weekday INTEGER, day_of_month INTEGER, nth INTEGER, end_date TEXT);
CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, amount_cents INTEGER NOT NULL CHECK(amount_cents > 0), type TEXT NOT NULL CHECK(type IN ('deposit','bill','purchase')), date TEXT NOT NULL, category_id INTEGER REFERENCES categories(id), note TEXT, priority INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('planned','paid')), paid_date TEXT, rule_id INTEGER REFERENCES recurring_rules(id), is_override INTEGER NOT NULL DEFAULT 0, deleted INTEGER NOT NULL DEFAULT 0, assignment_override INTEGER NOT NULL DEFAULT 0, assigned_deposit_item_id INTEGER REFERENCES items(id), assignment_note TEXT, moved_from_deposit_item_id INTEGER REFERENCES items(id), created_at TEXT NOT NULL, updated_at TEXT NOT NULL, moved_from_date TEXT);
CREATE TABLE balance_adjustments (id INTEGER PRIMARY KEY AUTOINCREMENT, amount_cents INTEGER NOT NULL, date TEXT NOT NULL, note TEXT, created_at TEXT NOT NULL);
CREATE TABLE audit_log (id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER, action TEXT NOT NULL, detail TEXT, created_at TEXT NOT NULL);
CREATE INDEX idx_items_date ON items(date);
CREATE INDEX idx_items_type ON items(type);
CREATE INDEX idx_items_rule ON items(rule_id);
CREATE INDEX idx_items_assignment ON items(assignment_override, assigned_deposit_item_id);
CREATE INDEX idx_audit_item ON audit_log(item_id);
INSERT INTO categories(id, name, color, kind, is_builtin, sort_order, income_type) VALUES
  (1, 'Housing', '#e05d7a', 'both', 1, 1, NULL), (2, 'Utilities', '#f2a6c0', 'both', 1, 2, NULL),
  (3, 'Food & Groceries', '#a48bf0', 'both', 1, 3, NULL), (4, 'Transportation', '#7c6bd6', 'both', 1, 4, NULL),
  (5, 'Entertainment', '#f6c6d8', 'both', 1, 5, NULL), (6, 'Shopping', '#d4b0f0', 'both', 1, 6, NULL),
  (7, 'Health', '#f0eafa', 'both', 1, 7, NULL), (8, 'Other', '#8b83a3', 'both', 1, 8, NULL),
  (9, 'Salary', '#2f9e7f', 'deposit', 1, 9, 'salary'), (10, 'Other Income', '#3aa97c', 'deposit', 1, 10, 'other');
INSERT INTO settings(key, value) VALUES ('first_run_complete', 'true');
INSERT INTO settings(key, value) VALUES ('include_other_income_in_pay_periods', 'true');
INSERT INTO recurring_rules(id, kind, anchor_date, weekday, day_of_month, nth, end_date) VALUES (700, 'monthly_date', '2026-08-05', NULL, 5, NULL, NULL);
INSERT INTO items(id, name, amount_cents, type, date, category_id, note, priority, status, paid_date, rule_id, is_override, deleted, assignment_override, assigned_deposit_item_id, assignment_note, moved_from_deposit_item_id, moved_from_date, created_at, updated_at) VALUES
  (800, 'August salary', 250000, 'deposit', '2026-08-01', 9, 'Electron fixture', 0, 'paid', '2026-08-01', NULL, 0, 0, 0, NULL, NULL, NULL, NULL, '2026-07-01T00:00:00Z', '2026-08-01T00:00:00Z'),
  (801, 'September salary', 250000, 'deposit', '2026-08-15', 9, NULL, 0, 'planned', NULL, NULL, 0, 0, 0, NULL, NULL, NULL, NULL, '2026-07-01T00:00:00Z', '2026-08-01T00:00:00Z'),
  (802, 'Moved rent', 120000, 'bill', '2026-08-16', 1, 'Moved after payday', 1, 'planned', NULL, 700, 1, 0, 1, 801, 'Pay later', 800, '2026-08-05', '2026-07-01T00:00:00Z', '2026-08-02T00:00:00Z'),
  (803, 'Deleted occurrence', 120000, 'bill', '2026-09-05', 1, NULL, 1, 'planned', NULL, 700, 1, 1, 0, NULL, NULL, NULL, '2026-09-05', '2026-07-01T00:00:00Z', '2026-08-02T00:00:00Z'),
  (804, 'Side work', 50000, 'deposit', '2026-08-10', 10, 'Other income', 0, 'paid', '2026-08-10', NULL, 0, 0, 0, NULL, NULL, NULL, NULL, '2026-07-01T00:00:00Z', '2026-08-10T00:00:00Z');
INSERT INTO balance_adjustments(id, amount_cents, date, note, created_at) VALUES (900, -1250, '2026-08-03', 'Electron adjustment', '2026-08-03T00:00:00Z');
INSERT INTO audit_log(id, item_id, action, detail, created_at) VALUES (1000, 802, 'move', 'Moved from 2026-08-05 to 2026-08-16 in deposit period 2026-08-15. Note: Pay later', '2026-08-02T00:00:00Z');
PRAGMA user_version = 6;
