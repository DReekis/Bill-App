# Google Play Console — App Access Review Credentials

> **Important**: Google Play requires developers to provide review credentials under **Policy and Programs ➔ App Content ➔ App Access** ("All or some functionality is restricted").
> Because automated test bots and human Google reviewers in the US/Europe cannot receive dynamic Indian SMS messages, the app has been configured with a **deterministic 2FA-bypass test account** with **full Pro access** to all features.

---

## 1. Quick Copy-Paste for Google Play Console Form

When submitting your app in the Google Play Console, navigate to:
**App Content** ➔ **App Access** ➔ Select **"All or some functionality is restricted"** ➔ Click **Add new instructions**.

| Form Field in Google Play Console | What to Enter / Copy-Paste |
| :--- | :--- |
| **Instruction Name** | `Full Access Reviewer Test Account` |
| **Username / Phone Number** | `9999999999` |
| **Password / OTP** | `123456` |
| **Any other instructions** | *(Copy the text block below)* |

### Text for the "Any other instructions" Field:
```text
This is a dedicated test account configured with full access to all features (Business Pro plan):

1. On the Welcome / Login screen, ensure "Business Owner" is selected.
2. Enter Mobile Number: 9999999999 (you can also tap the "Auto-Fill" button under Reviewer / Demo Access).
3. Tap "Get OTP".
4. Enter 6-digit static test code: 123456 (also accepts 1234).
5. Tap "Verify & Continue".

The account will instantly unlock with:
- Business: Billket Superstore (GSTIN: 29AABCU9603R1ZM)
- Active Plan: Business Pro (Unlimited Invoices, Inventory, Customers, E-Way Bill, E-Invoice, Cash & Bank Hub, Financial Reports)
- Pre-populated demo store products, customers, suppliers, and finalized invoices.

No SMS gateway or network OTP delivery is required. If testing in airplane / offline mode, tap "Continue Offline (Local Storage)".

Staff Login (Optional):
Switch to "Staff / Employee" tab, enter Phone: 9999900001, tap Continue, and enter PIN: 1234.
```

---

## 2. Credentials Reference Table

| Persona | Phone Number / User | Static OTP / PIN | Subscription Plan | Role & Permissions | Preloaded Demo Data |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Primary: Business Owner** *(Recommended)* | `9999999999` | `123456` *(or `1234`)* | **Business Pro** *(Active, 10 years)* | **Owner** (Full unrestricted access to all modules) | Products, Customers, Suppliers, Invoices, Bank Accounts |
| **Secondary: Business Owner** *(Backup)* | `9876543210` | `123456` *(or `1234`)* | **Business Pro** *(Active, 10 years)* | **Owner** (Full unrestricted access to all modules) | Products, Customers, Suppliers, Invoices, Bank Accounts |
| **Staff Member** *(POS / Counter)* | `9999900001` | `1234` | Managed by Owner | **Cashier** (Fast billing, POS counter access) | Connected to Billket Superstore |

---

## 3. How the Features are Unlocked for Reviewers

- **Reviewer enters `9999999999` + `123456`**
- **Bypasses 2Factor SMS Gateway in all environments** (Production, Staging, Dev, Test)
- **Backend links `playstore.test@billapp.in` with Owner Role**
- **Activates `Business Pro` Tier** (Full unrestricted access to all enterprise modules)
- **Seeds `Billket Superstore` (GSTIN: `29AABCU9603R1ZM`)**
- **Pre-populates Products, Invoices, Customers & Bank Accounts**
- **Lands directly on the Dashboard (`AppShell`)** (Bypasses any setup wizards or roadblock forms)

### Feature Access Verification Matrix:

| Feature / Module | Status for Reviewer | Verification Path in App |
| :--- | :---: | :--- |
| **GST Billing & Invoicing** | **UNLIMITED** | Tap **New Bill (+)** ➔ Select Customer & Product ➔ Generate GST bill with CGST/SGST/IGST. |
| **PDF & Thermal Print** | **UNLOCKED** | View any Invoice ➔ Tap **Share / Print** ➔ 58mm / 80mm thermal receipt & GST tax invoice PDF. |
| **Inventory Management** | **UNLIMITED** | **Inventory Tab** ➔ Search by SKU/Barcode, stock level alerts, cost averaging. |
| **E-Invoice & E-Way Bill** | **UNLOCKED** | **More ➔ Compliance Hub** ➔ E-Invoice & E-Way Bill generation unlocked by Pro tier. |
| **Banking & Cash Flow** | **UNLOCKED** | **More ➔ Cash & Bank Hub** ➔ HDFC Current Account preloaded with ₹2,50,000 balance. |
| **Quotations & Sales Orders** | **UNLOCKED** | **Orders Tab** ➔ Quotations, Sales Orders, Purchase Orders, Delivery Challans. |
| **Financial Reports** | **UNLOCKED** | **More ➔ Reports** ➔ GSTR-1, GSTR-3B, Profit & Loss, Day Book, Balance Sheet. |
| **Cloud Auto-Sync** | **ENABLED** | Background delta sync to cloud instance (`http://43.204.237.49`). |
| **Offline First** | **ENABLED** | SQLite local sovereignty ensures app functions with zero internet. |
