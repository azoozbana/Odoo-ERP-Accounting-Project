Odoo ERP Accounting Practice Project

A self-directed practice project: I set up Odoo 20 Community Edition for a fictional Saudi trading company (Al-Noor Trading), processed three months of accounting transactions, and then built the financial reports myself with SQL queries against Odoo's PostgreSQL database.

This is a practice project on made-up data. It is not a live company implementation.

What I did

1. Setup

Installed Odoo 20 Community Edition (local Windows install, PostgreSQL backend).
Used the Saudi Arabia localization: SAR currency, Saudi chart of accounts, 15% VAT.
Odoo Community leaves out some accounting screens, so I installed an open-source accounting addon (om_account_accountant, from Odoo Mates) to get the general ledger, journal entry and financial report screens.
Created master data: customers (with 15-digit VAT numbers), vendors, and products, including goods, a service, and a fixed asset.

2. Three months of transactions (Jan to Mar 2026)

Month	Activity
January	SAR 500,000 owner's capital; delivery van purchase (65,000 + VAT, paid); merchandise purchase (23,000 + VAT); first customer invoice (7,200 + VAT); depreciation; cost of goods sold
February	Partial customer payment (4,140); supplier payment (26,450); credit note for a returned item (850 + VAT); electronics bill (12,600 + VAT, still open); 3-month prepaid rent bill (15,000 + VAT, paid); depreciation; rent amortization; cost of goods sold reversal for the return (400)
March	Second customer invoice (12,550 + VAT, still open); final payment from first customer (3,162.50); depreciation; rent amortization; cost of goods sold (6,600)

3. Month-end adjusting entries, posted manually

Straight-line depreciation on the van: 65,000 / 60 months = 1,083.33 per month.
Prepaid rent amortized in equal monthly amounts (5,000).
Cost of goods sold (quantity sold x unit cost) with inventory reduced, and reversed for the returned item.

4. SQL reports from Odoo's database (sql/odoo_financial_reports.sql) Trial balance, income statement, balance sheet, VAT summary by quarter, aged receivables, and control checks. All queries are read-only and count posted entries only.

How inventory was handled

I turned off "Track Inventory" in Odoo. Purchases of goods are debited to Inventory - Goods for Resale, and cost of goods sold is posted by a manual journal entry each month (Dr Cost of Goods Sold / Cr Inventory), calculated from quantities sold and unit costs. In accounting terms this is a perpetual-style approach with month-end entries, done by hand. It is not a periodic system.

One correction entry: January's cost of goods sold was first posted to a different account (400800). On 31 March I posted a reclass entry (Dr 400100 / Cr 400800, 3,500) so all cost of goods sold sits in one account.

Results (as of 31 March 2026)
Report	Result
Trial balance	Net balance 0.00. Total debits equal total credits (809,632.49 each, including the reclass entry)
Income statement	Revenue 18,900.00; cost of goods sold 9,700.00; rent 10,000.00; depreciation 3,249.99; net loss (4,049.99)
Balance sheet	Assets 513,275.01 = liabilities 17,325.00 + equity 495,950.01 (share capital 500,000.00 less the 4,049.99 loss). Check row = 0.00
VAT, Q1 2026	Output VAT 2,835.00; input VAT 17,340.00; net (14,505.00), a refundable position
Aged receivables	One open invoice: 14,432.50, due 4 April 2026, not yet due at 31 March
Control checks	Trial balance difference 0.00; output VAT is exactly 15.00% of net sales

The income statement figures matched Odoo's own income statement export.

What the numbers show

The quarter's loss comes from fixed costs: gross profit was 9,200 (48.7% margin), while rent (10,000) and depreciation (3,249.99) were higher.
The VAT position is a refund because input VAT on the van, stock and prepaid rent (17,340) is larger than output VAT on three months of sales (2,835).
Open items at 31 March: receivable 14,432.50 and payable 14,490.00.
Limitations
No VAT return or settlement entry was posted. The VAT report shows the position only.
No bank feed or statement import. Payments were registered directly in Odoo. The opening capital was recorded through Odoo's bank statement workflow.
Simplified conventions: a full month of depreciation from the month of purchase, and equal monthly rent amortization.
No payroll, bad debt allowance or accrued expenses.
One company and one currency.
The SQL was written and tested on Odoo 20 only. Table and column names may differ in other versions.
Running the queries
Connect to the Odoo PostgreSQL database with any SQL client (I used VS Code with a PostgreSQL extension).
Run the sections of sql/odoo_financial_reports.sql one at a time.
All queries are SELECT only. Never edit Odoo's tables directly.
Account codes sit in a jsonb column keyed by company id (code_store ->> '1'). Change the key if you use a different company.

Database credentials are not included in this repository.

Repository structure
Odoo-ERP-Accounting-Project/
├── README.md
├── sql/
│   └── odoo_financial_reports.sql
└── docs/
    ├── general_ledger_export.csv
    └── screenshots/
Contact

Abdulaziz Mohammed Banafa | Jeddah, Saudi Arabia LinkedIn: linkedin.com/in/abdulazizbanafa Email: Azoozbanafea666@outlook.com
